/// 文章导入的编排：预览 → 分段预览 → 合并 → 提交。
///
/// 对应旧版 `src/modules/article-import/service.ts`（419 行）与
/// `app/api/article-import/{preview,merge,commit}/route.ts`。
///
/// **与旧版的差异（逐条）**：
/// 1. 没有 HTTP 层：三个路由变成三个方法，错误直接抛 [AppError]；
/// 2. 预览存在**内存**里（旧版落 `import_previews` 表并靠 SQL 清理过期行），
///    有效期同样由 [importPreviewTtlMs] 决定，过期与消费语义不变；
/// 3. 预览级 AI 状态直接挂在预览对象上（旧版塞进 `rows_json` 首行的 `_meta`，
///    那是为了不给表加列）；
/// 4. 提交**不写** `import_batches` / `import_rows`：那两张表是 CSV 导入的
///    审计与撤销底座（`CsvImportService` 的「撤销批次」会读它们），
///    文章导入没有撤销入口，写进去只会让 CSV 的导入历史多出一批无法撤销、
///    也无法解释来源的批次；
/// 5. 提交逐条走 `WordEditService`（每个词条各自成事务），旧版是整批一个事务。
///    幂等性由 `WordEditService.create` 的既有判重保证：重复提交只会把
///    已建词条记成「已存在」，因此中途失败重试即可收敛。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/article_import/article_ai_models.dart';
import 'package:lexiloop/domain/article_import/article_candidates.dart';
import 'package:lexiloop/domain/article_import/article_extract.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/text/normalizer.dart';
import 'package:lexiloop/services/article_import/article_ai_selector.dart';
import 'package:lexiloop/services/dictionary/selection.dart';
import 'package:lexiloop/services/learning_progress_reset.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// 文章导入服务。
class ArticleImportService {
  /// 以数据库、设置服务、词条写入服务与 AI 选词器构造。
  new(this._db, this._settings, this._words, this._selector);

  final AppDatabase _db;
  final SettingsService _settings;
  final WordEditService _words;
  final ArticleAiSelector _selector;

  /// 内存中的预览（令牌 → 预览）。旧版对应 `import_previews` 表。
  final Map<String, ArticleImportPreview> _previews =
      <String, ArticleImportPreview>{};

  // ── 预览 ──

  /// 生成一次文章预览。
  ///
  /// 流程与旧版 `createArticlePreview` 一致：校验长度 → 提取词形 →
  /// 拉已有词条做 KNOWN/CANDIDATE 判定 → AI 选词 → 合并 → 登记预览。
  /// AI 未配置或失败时**回退本地筛选**，并把原因写进 `aiError`。
  Future<ArticleImportPreview> preview({
    required String articleText,
    required int now,
    String sourceLanguage = articleDefaultSourceLanguage,
    String targetLanguage = articleDefaultTargetLanguage,
    List<VocabularyLevel>? examTargets,
    ArticleDifficultyMode difficultyMode = ArticleDifficultyMode.atOrAbove,
    ArticleExtractScope extractScope = ArticleExtractScope.wordsOnly,
  }) async {
    final rawText = _clampArticleText(articleText);
    final extraction = extractArticleTerms(
      rawText,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    if (extraction.extracted.isEmpty) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '未能从文章中提取到有效单词，请检查是否为英文文章。',
      );
    }
    final context = await _buildContext(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      cleaned: extraction.cleaned,
      examTargets: examTargets,
      difficultyMode: difficultyMode,
      extractScope: extractScope,
    );
    final outcome = await _applyAiSelection(
      context: context,
      extraction: extraction,
    );
    return _store(
      _assemblePreview(
        context: context,
        extraction: extraction,
        outcome: outcome,
        charCount: rawText.length,
        now: now,
      ),
      now,
    );
  }

  /// 分段预览：按批并发分析，**每完成一批就产出一个事件**。
  ///
  /// 旧版在 `article-tab.tsx` 里用 `ARTICLE_SEGMENT_CONCURRENCY` 个 worker
  /// 拉取批次并即时合并展示；这里把同一件事做成流，界面按到达顺序合并，
  /// 已解析的批次立刻可见。
  Stream<ArticleSegmentOutcome> previewSegments({
    required String articleText,
    required int segmentsPerBatch,
    required int now,
    List<VocabularyLevel>? examTargets,
    ArticleDifficultyMode difficultyMode = ArticleDifficultyMode.atOrAbove,
    ArticleExtractScope extractScope = ArticleExtractScope.wordsOnly,
  }) {
    final plan = buildArticleSegmentPlan(
      articleText,
      segmentsPerBatch: segmentsPerBatch,
    );
    final controller = StreamController<ArticleSegmentOutcome>();
    unawaited(
      _driveBatches(
        controller: controller,
        plan: plan,
        options: _SegmentOptions(
          examTargets: examTargets,
          difficultyMode: difficultyMode,
          extractScope: extractScope,
          now: now,
        ),
      ),
    );
    return controller.stream;
  }

  // ── 合并 ──

  /// 把多个分段预览合并成一个可提交的预览。
  ///
  /// 对应旧版 `mergeArticlePreviews`（服务端版本）：按令牌去重 → 合并候选 →
  /// 按当前词库重新判定 KNOWN → 按难度截断短语与句子 → 合并统计与 AI 状态。
  Future<ArticleImportPreview> mergePreviews({
    required List<String> tokens,
    required int now,
  }) async {
    if (tokens.isEmpty) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '请选择至少一个段落预览进行合并。',
      );
    }
    if (tokens.length > maxArticleSegments) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '最多合并 $maxArticleSegments 个段落。',
      );
    }
    _purgeExpired(now);
    final previews = <ArticleImportPreview>[];
    // 令牌去重：旧版服务端合并不去重，但客户端永远只送唯一令牌；本版在服务层
    // 去重，使「同一批被传两次」不会把出现次数与统计翻倍。
    final seen = <String>{};
    for (final token in tokens) {
      final stored = _previews[token];
      if (stored == null) {
        throw ValidationError(
          AppErrorCode.importPreviewExpired,
          details: '段落预览已过期或不存在：${_shortToken(token)}',
        );
      }
      if (seen.add(token)) previews.add(stored);
    }
    return _store(await _mergeStored(previews, now), now);
  }

  // ── 提交 ──

  /// 提交预览中选中的词条，并为新建词条入队初始化任务。
  ///
  /// 令牌会被**消费**（旧版提交时 `DELETE FROM import_previews`）：同一个
  /// 预览不可能被提交两次。重复提交同一篇文章时，`WordEditService.create`
  /// 的判重会把它们记成「已存在」，不会产生重复词条。
  ///
  /// **没有 `resetLearningProgress` 参数**：旧版那枚开关要删复习日志 / 卡片 /
  /// 错词状态并撤下未作答题，实现只存在于 `CsvImportService` 内部（私有），
  /// 而本工作流不允许改动它或 `WordEditService`。因此文章导入不提供该开关，
  /// 界面上也不显示——摆一个做不到的复选框比没有它更糟。
  /// [resetLearningProgress] 对应旧版 `article-tab.tsx:475,526` 的
  /// 「重置本次已有词条的学习进度」：勾上之后，**本次命中的已有词条**会被
  /// 清空复习历史（见 [resetLearningProgressNow]）。新建的词条不受影响。
  Future<ArticleCommitResult> commit({
    required String previewToken,
    required Set<String> selectedKeys,
    required ImportMode mode,
    required int now,
    bool resetLearningProgress = false,
    bool includeSourceSentence = true,
    List<String> tags = const <String>[],
  }) async {
    _purgeExpired(now);
    final preview = _previews.remove(previewToken);
    if (preview == null) {
      throw const ValidationError(
        AppErrorCode.importPreviewExpired,
        details: '预览已过期或已提交。',
      );
    }
    final selected = _selectedCandidates(preview, selectedKeys);
    if (selected.isEmpty) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '请至少选择一个词条再导入。',
      );
    }
    final settings = await _settings.load();
    final options = _CommitOptions(
      preview: preview,
      mode: mode,
      now: now,
      resetAt: resetAtFor(mode, requested: resetLearningProgress, now: now),
      includeSourceSentence: includeSourceSentence,
      tags: _cleanTags(tags),
      dictionaryProviders: _dictionaryProvidersFor(settings),
    );
    final counters = _CommitCounters();
    for (final candidate in selected) {
      await _commitCandidate(candidate, options, counters);
    }
    return ArticleCommitResult(
      createdWords: counters.created,
      existingWords: counters.existing,
      queuedInitializations: counters.queued,
      createdWordIds: List<int>.unmodifiable(counters.createdWordIds),
      affectedWordIds: List<int>.unmodifiable(counters.affectedWordIds),
    );
  }

  // ── 预览内部实现 ──

  String _clampArticleText(String raw) {
    final text = unorm.nfkc(raw);
    if (text.trim().length < minArticleChars) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '文章至少需要 $minArticleChars 个字符。',
      );
    }
    if (text.length > maxArticleChars) {
      throw const ValidationError(
        AppErrorCode.validationError,
        details: '文章不能超过 $maxArticleChars 字符。',
      );
    }
    return text;
  }

  Future<_PreviewContext> _buildContext({
    required String sourceLanguage,
    required String targetLanguage,
    required String cleaned,
    required List<VocabularyLevel>? examTargets,
    required ArticleDifficultyMode difficultyMode,
    required ArticleExtractScope extractScope,
  }) async {
    final settings = await _settings.load();
    return _PreviewContext(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      existing: await _existingTerms(sourceLanguage, targetLanguage),
      sentences: _candidateSentences(cleaned),
      examTargets: examTargets ?? settings.examTargets,
      difficultyMode: difficultyMode,
      extractScope: extractScope,
    );
  }

  /// 该语言方向下的全部已有词条（归一化词形 + 内容类型）。
  ///
  /// 兼容历史 CSV 导入写成 `'zh'` 的旧数据：目标语言为 `'zh-CN'` 时一并
  /// 纳入判重，避免已导入的词在文章分词里重复显示为生词。
  Future<List<_ExistingTerm>> _existingTerms(
    String sourceLanguage,
    String targetLanguage,
  ) async {
    final targets = targetLanguage == 'zh-CN'
        ? const <String>['zh-CN', 'zh']
        : <String>[targetLanguage];
    final query = _db.select(_db.words)
      ..where(
        (table) =>
            table.sourceLanguage.equals(sourceLanguage) &
            table.targetLanguage.isIn(targets),
      );
    final rows = await query.get();
    return <_ExistingTerm>[
      for (final row in rows)
        _ExistingTerm(
          normalizedTerm: row.normalizedTerm,
          contentType: row.contentType,
        ),
    ];
  }

  List<String> _candidateSentences(String cleaned) {
    final out = <String>[];
    for (final sentence in extractSentences(cleaned)) {
      if (sentence.length < articleSentenceMinChars) continue;
      out.add(sentence);
      if (out.length >= articleSentenceCandidateLimit) break;
    }
    return out;
  }

  /// 本地候选：词形 + 出现次数 + KNOWN/CANDIDATE 判定 + 出处句。
  List<ArticleCandidate> _wordCandidates(
    ArticleExtraction extraction,
    _PreviewContext context,
  ) {
    final knownWords = <String>{
      for (final term in context.existing)
        if (term.contentType == LexicalContentType.word)
          articleNormalizedLookupKey(term.normalizedTerm),
    };
    final out = <ArticleCandidate>[];
    for (final item in extraction.extracted) {
      if (out.length >= maxArticleCandidates) break;
      final known = knownWords.contains(
        articleNormalizedLookupKey(item.normalizedTerm),
      );
      out.add(
        ArticleCandidate(
          term: item.term,
          normalizedTerm: item.normalizedTerm,
          occurrences: item.occurrences,
          status: known
              ? ArticleCandidateStatus.known
              : ArticleCandidateStatus.candidate,
          entryType: LexicalContentType.word,
          sourceSentence: _sentenceFor(item.term, context.sentences),
        ),
      );
    }
    return out;
  }

  /// 把候选送进 AI，并把结果合回候选列表。
  Future<_AiOutcome> _applyAiSelection({
    required _PreviewContext context,
    required ArticleExtraction extraction,
  }) async {
    final candidates = _wordCandidates(extraction, context);
    final fallbackTerms = _candidateTerms(candidates);
    final aiCandidates = _aiCandidates(candidates);
    if (aiCandidates.isEmpty) {
      return _AiOutcome(
        candidates: candidates,
        recommendedTerms: fallbackTerms,
        aiApplied: false,
      );
    }
    final result = await _selector.select(
      ArticleAiSelectInput(
        articleText: _aiArticleText(extraction.cleaned, context.sentences),
        candidates: aiCandidates,
        knownSample: <String>[
          for (final term in context.existing.take(articleKnownSampleLimit))
            term.normalizedTerm,
        ],
        totalKnown: context.existing.length,
        examTargets: context.examTargets,
        difficultyMode: context.difficultyMode,
        extractScope: context.extractScope,
      ),
    );
    if (!result.applied) {
      return _AiOutcome(
        candidates: candidates,
        recommendedTerms: fallbackTerms,
        aiApplied: false,
        aiError: result.error ?? 'AI 选词失败，已回退为本地筛选。',
      );
    }
    return _mergeAiResult(
      candidates: candidates,
      result: result,
      context: context,
      cleanedArticle: extraction.cleaned,
      fallbackTerms: fallbackTerms,
    );
  }

  _AiOutcome _mergeAiResult({
    required List<ArticleCandidate> candidates,
    required ArticleAiSelection result,
    required _PreviewContext context,
    required String cleanedArticle,
    required List<String> fallbackTerms,
  }) {
    final knownWords = _knownWordKeys(context.existing);
    final matchedAi = <String>{};
    final words = _mergeAiWords(
      candidates: candidates,
      aiWords: result.words,
      context: context,
      cleanedLower: cleanedArticle.toLowerCase(),
      knownWords: knownWords,
      matchedAi: matchedAi,
    );
    final selected = <String>{
      for (final word in result.words)
        articleNormalizedLookupKey(
          normalizeTerm(word.term, context.sourceLanguage),
        ),
    };
    final recommended = result.words.isEmpty
        ? fallbackTerms
        : <String>[
            for (final candidate in words)
              if (candidate.isCandidate &&
                  selected.contains(
                    articleNormalizedLookupKey(candidate.normalizedTerm),
                  ))
                candidate.normalizedTerm.toLowerCase(),
          ];
    final merged = <ArticleCandidate>[
      ...words,
      ..._aiPhraseCandidates(result, context, words),
      ..._aiSentenceCandidates(result, context, words),
    ];
    return _AiOutcome(
      candidates: merged,
      recommendedTerms: recommended,
      aiApplied: result.hasContent,
      aiError: result.error,
    );
  }

  /// 合并 LLM 分词结果与本地词形：支持词形还原（surface → lemma）与
  /// 正文直接抽取（不被 top-200 词频截断丢弃）。
  List<ArticleCandidate> _mergeAiWords({
    required List<ArticleCandidate> candidates,
    required List<ArticleAiWord> aiWords,
    required _PreviewContext context,
    required String cleanedLower,
    required Set<String> knownWords,
    required Set<String> matchedAi,
  }) {
    final byTerm = <String, ArticleAiWord>{};
    final bySurface = <String, ArticleAiWord>{};
    for (final word in aiWords) {
      byTerm[articleNormalizedLookupKey(word.term)] = word;
      final surface = word.surfaceForm;
      if (surface != null && surface.isNotEmpty) {
        bySurface[articleNormalizedLookupKey(surface)] = word;
      }
    }
    final mapped = <ArticleCandidate>[
      for (final candidate in candidates)
        _mapWordCandidate(
          candidate: candidate,
          byTerm: byTerm,
          bySurface: bySurface,
          context: context,
          knownWords: knownWords,
          matchedAi: matchedAi,
        ),
    ];
    for (final word in aiWords) {
      final key = articleNormalizedLookupKey(word.term);
      if (matchedAi.contains(key)) continue;
      if (!_wordAppearsInArticle(word, cleanedLower)) continue;
      mapped.add(_newAiWordCandidate(word, context, knownWords));
    }
    return mergeArticleCandidates(mapped);
  }

  ArticleCandidate _mapWordCandidate({
    required ArticleCandidate candidate,
    required Map<String, ArticleAiWord> byTerm,
    required Map<String, ArticleAiWord> bySurface,
    required _PreviewContext context,
    required Set<String> knownWords,
    required Set<String> matchedAi,
  }) {
    final key = articleNormalizedLookupKey(candidate.term);
    final direct = byTerm[key];
    if (direct != null) {
      matchedAi.add(articleNormalizedLookupKey(direct.term));
      return _withAiMeta(candidate, direct);
    }
    final lemmatized = bySurface[key];
    if (lemmatized == null) return candidate;
    matchedAi.add(articleNormalizedLookupKey(lemmatized.term));
    final normalized = normalizeTerm(lemmatized.term, context.sourceLanguage);
    final isKnown = knownWords.contains(articleNormalizedLookupKey(normalized));
    return ArticleCandidate(
      term: lemmatized.term,
      normalizedTerm: normalized,
      occurrences: candidate.occurrences,
      status: isKnown
          ? ArticleCandidateStatus.known
          : ArticleCandidateStatus.candidate,
      entryType: LexicalContentType.word,
      sourceSentence:
          candidate.sourceSentence ??
          _sentenceForWord(lemmatized, context.sentences),
      surfaceForm: lemmatized.surfaceForm ?? candidate.term,
      aiReason: lemmatized.reason,
      difficulty: lemmatized.difficulty,
      cefrLevel: lemmatized.cefrLevel,
      frequency: lemmatized.frequency,
      examTags: lemmatized.examTags,
    );
  }

  ArticleCandidate _newAiWordCandidate(
    ArticleAiWord word,
    _PreviewContext context,
    Set<String> knownWords,
  ) {
    final normalized = normalizeTerm(word.term, context.sourceLanguage);
    final isKnown = knownWords.contains(articleNormalizedLookupKey(normalized));
    return ArticleCandidate(
      term: word.term,
      normalizedTerm: normalized,
      occurrences: 1,
      status: isKnown
          ? ArticleCandidateStatus.known
          : ArticleCandidateStatus.candidate,
      entryType: LexicalContentType.word,
      sourceSentence: _sentenceForWord(word, context.sentences),
      surfaceForm: word.surfaceForm,
      aiReason: word.reason,
      difficulty: word.difficulty,
      cefrLevel: word.cefrLevel,
      frequency: word.frequency,
      examTags: word.examTags,
    );
  }

  bool _wordAppearsInArticle(ArticleAiWord word, String cleanedLower) {
    if (cleanedLower.contains(word.term.toLowerCase())) return true;
    final surface = word.surfaceForm;
    return surface != null &&
        surface.isNotEmpty &&
        cleanedLower.contains(surface.toLowerCase());
  }

  String? _sentenceForWord(ArticleAiWord word, List<String> sentences) {
    final surface = word.surfaceForm;
    if (surface != null && surface.isNotEmpty) {
      final hit = _sentenceFor(surface, sentences);
      if (hit != null) return hit;
    }
    return _sentenceFor(word.term, sentences);
  }

  Set<String> _knownWordKeys(List<_ExistingTerm> existing) => <String>{
    for (final term in existing)
      if (term.contentType == LexicalContentType.word)
        articleNormalizedLookupKey(term.normalizedTerm),
  };

  /// 把 AI 的单词元数据（理由 / 难度 / CEFR / 词频 / 变形 / 考试标签）写回候选。
  ArticleCandidate _withAiMeta(
    ArticleCandidate candidate,
    ArticleAiWord? meta,
  ) {
    if (meta == null) return candidate;
    return ArticleCandidate(
      term: candidate.term,
      normalizedTerm: candidate.normalizedTerm,
      occurrences: candidate.occurrences,
      status: candidate.status,
      entryType: candidate.entryType,
      sourceSentence: candidate.sourceSentence,
      surfaceForm: meta.surfaceForm ?? candidate.surfaceForm,
      aiReason: meta.reason,
      difficulty: meta.difficulty,
      cefrLevel: meta.cefrLevel,
      frequency: meta.frequency,
      examTags: meta.examTags.isEmpty ? candidate.examTags : meta.examTags,
      aiCard: candidate.aiCard,
    );
  }

  /// AI 返回的短语候选。
  ///
  /// 旧版这里写了一个 `status: existingNorm ? KNOWN : CANDIDATE`，但
  /// `existingNorm` 恒为 false（已在上面被 `continue` 挡掉），是死分支；
  /// 本版直接写 CANDIDATE。
  List<ArticleCandidate> _aiPhraseCandidates(
    ArticleAiSelection result,
    _PreviewContext context,
    List<ArticleCandidate> current,
  ) {
    final seen = _seenKeys(current, context.existing);
    final out = <ArticleCandidate>[];
    for (final phrase in result.phrases.take(articlePhraseLimit)) {
      final normalized = normalizeTerm(phrase.term, context.sourceLanguage);
      if (!seen.add(
        articleCandidateKey(LexicalContentType.phrase, normalized),
      )) {
        continue;
      }
      out.add(
        ArticleCandidate(
          term: phrase.term,
          normalizedTerm: normalized,
          occurrences: 1,
          status: ArticleCandidateStatus.candidate,
          entryType: LexicalContentType.phrase,
          sourceSentence: _sentenceFor(phrase.term, context.sentences),
          aiReason: phrase.reason,
          difficulty: phrase.difficulty,
          cefrLevel: phrase.cefrLevel,
          aiCard: phrase.toCard(),
        ),
      );
    }
    return out;
  }

  /// AI 返回的句子候选。
  List<ArticleCandidate> _aiSentenceCandidates(
    ArticleAiSelection result,
    _PreviewContext context,
    List<ArticleCandidate> current,
  ) {
    final seen = _seenKeys(current, context.existing);
    final out = <ArticleCandidate>[];
    for (final sentence in result.sentences.take(articleSentenceLimit)) {
      final text = sentence.sentence.trim();
      final normalized = normalizeTerm(text, context.sourceLanguage);
      if (!seen.add(
        articleCandidateKey(LexicalContentType.sentence, normalized),
      )) {
        continue;
      }
      out.add(
        ArticleCandidate(
          term: text,
          normalizedTerm: normalized,
          occurrences: 1,
          status: ArticleCandidateStatus.candidate,
          entryType: LexicalContentType.sentence,
          sourceSentence: text,
          aiCard: sentence.toCard(),
        ),
      );
    }
    return out;
  }

  Set<String> _seenKeys(
    List<ArticleCandidate> current,
    List<_ExistingTerm> existing,
  ) => <String>{
    for (final candidate in current)
      articleCandidateKey(candidate.entryType, candidate.normalizedTerm),
    for (final term in existing)
      articleCandidateKey(term.contentType, term.normalizedTerm),
  };

  ArticleImportPreview _assemblePreview({
    required _PreviewContext context,
    required ArticleExtraction extraction,
    required _AiOutcome outcome,
    required int charCount,
    required int now,
  }) {
    final candidates = outcome.candidates;
    return ArticleImportPreview(
      previewToken: _newToken(),
      filename: '文章 · ${extraction.wordCount} 词 · $charCount 字符',
      sourceLanguage: context.sourceLanguage,
      targetLanguage: context.targetLanguage,
      articleStats: ArticleStats(
        charCount: charCount,
        wordCount: extraction.wordCount,
        uniqueCount: extraction.extracted.length,
        knownCount: candidates.where((c) => c.isKnown).length,
        unknownCount: candidates.where((c) => c.isCandidate).length,
        phraseCount: candidates
            .where((c) => c.entryType == LexicalContentType.phrase)
            .length,
        sentenceCount: candidates
            .where((c) => c.entryType == LexicalContentType.sentence)
            .length,
      ),
      candidates: List<ArticleCandidate>.unmodifiable(candidates),
      recommendedTerms: outcome.recommendedTerms,
      recommendedKeys: recommendedCandidateKeys(
        candidates,
        outcome.recommendedTerms,
      ),
      aiApplied: outcome.aiApplied,
      aiError: outcome.aiError,
      totalCandidates: candidates.length,
      knownCount: candidates.where((c) => c.isKnown).length,
      expiresAt: now + importPreviewTtlMs,
    );
  }

  // ── 分段内部实现 ──

  Future<void> _driveBatches({
    required StreamController<ArticleSegmentOutcome> controller,
    required ArticleSegmentPlan plan,
    required _SegmentOptions options,
  }) async {
    final texts = <String, String>{
      for (final segment in plan.segments) segment.id: segment.text,
    };
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final index = next;
        next += 1;
        if (index >= plan.batches.length) return;
        controller.add(await _runBatch(plan.batches[index], texts, options));
      }
    }

    await Future.wait(<Future<void>>[
      for (
        var index = 0;
        index < math.min(articleSegmentConcurrency, plan.batches.length);
        index += 1
      )
        worker(),
    ]);
    await controller.close();
  }

  Future<ArticleSegmentOutcome> _runBatch(
    ArticleBatch batch,
    Map<String, String> texts,
    _SegmentOptions options,
  ) async {
    try {
      final combined = <String>[
        for (final id in batch.segmentIds) texts[id] ?? '',
      ].join(articleParagraphSeparator);
      return ArticleSegmentOutcome.success(
        batchIndex: batch.batchIndex,
        preview: await preview(
          articleText: combined,
          examTargets: options.examTargets,
          difficultyMode: options.difficultyMode,
          extractScope: options.extractScope,
          now: options.now,
        ),
      );
    } on AppError catch (error) {
      // 单批失败不能拖垮整次分析：把原因挂在这一批上，界面单独提供重试。
      return ArticleSegmentOutcome.failure(
        batchIndex: batch.batchIndex,
        error: articleImportErrorMessage(error),
      );
    }
  }

  // ── 合并内部实现 ──

  Future<ArticleImportPreview> _mergeStored(
    List<ArticleImportPreview> previews,
    int now,
  ) async {
    final first = previews.first;
    final merged = mergeArticleCandidates(<ArticleCandidate>[
      for (final preview in previews) ...preview.candidates,
    ]);
    final existing = await _existingTerms(
      first.sourceLanguage,
      first.targetLanguage,
    );
    final rechecked = _recheckKnown(merged, existing);
    final capped = _capByType(rechecked);
    final recommended = _mergedRecommendedTerms(previews, capped);
    return ArticleImportPreview(
      previewToken: _newToken(),
      filename: '合并预览 · ${previews.length} 段 · ${capped.length} 候选',
      sourceLanguage: first.sourceLanguage,
      targetLanguage: first.targetLanguage,
      articleStats: _mergedStats(previews, capped),
      candidates: List<ArticleCandidate>.unmodifiable(capped),
      recommendedTerms: recommended,
      recommendedKeys: recommendedCandidateKeys(capped, recommended),
      aiApplied:
          previews.any((preview) => preview.aiApplied) ||
          capped.any(
            (candidate) =>
                candidate.aiReason != null || candidate.aiCard != null,
          ),
      aiError: mergeAiErrors(previews),
      totalCandidates: capped.length,
      knownCount: capped.where((candidate) => candidate.isKnown).length,
      expiresAt: now + importPreviewTtlMs,
    );
  }

  /// 按当前词库重新判定 KNOWN。
  ///
  /// 合并可能把「某一批里是 KNOWN」的候选与「另一批里是 CANDIDATE」的同键
  /// 候选并到一起，而这一批与那一批之间用户可能已经提交过词条。
  List<ArticleCandidate> _recheckKnown(
    List<ArticleCandidate> candidates,
    List<_ExistingTerm> existing,
  ) {
    final keys = <String>{
      for (final term in existing)
        articleCandidateKey(term.contentType, term.normalizedTerm),
    };
    final wordKeys = <String>{
      for (final term in existing)
        if (term.contentType == LexicalContentType.word)
          articleNormalizedLookupKey(term.normalizedTerm),
    };
    return <ArticleCandidate>[
      for (final candidate in candidates)
        if (_knownInDb(candidate, keys, wordKeys))
          candidate.withStatus(ArticleCandidateStatus.known)
        else
          candidate,
    ];
  }

  bool _knownInDb(
    ArticleCandidate candidate,
    Set<String> keys,
    Set<String> wordKeys,
  ) {
    if (keys.contains(
      articleCandidateKey(candidate.entryType, candidate.normalizedTerm),
    )) {
      return true;
    }
    if (candidate.entryType != LexicalContentType.word) return false;
    return wordKeys.contains(
      articleNormalizedLookupKey(candidate.normalizedTerm),
    );
  }

  /// 全局截断短语与句子（按难度降序），单词不截断。
  List<ArticleCandidate> _capByType(List<ArticleCandidate> candidates) =>
      <ArticleCandidate>[
        for (final candidate in candidates)
          if (candidate.entryType == LexicalContentType.word) candidate,
        ..._topByDifficulty(
          candidates,
          LexicalContentType.phrase,
          articlePhraseLimit,
        ),
        ..._topByDifficulty(
          candidates,
          LexicalContentType.sentence,
          articleSentenceLimit,
        ),
      ];

  List<ArticleCandidate> _topByDifficulty(
    List<ArticleCandidate> candidates,
    LexicalContentType type,
    int limit,
  ) {
    final matching = <ArticleCandidate>[
      for (final candidate in candidates)
        if (candidate.entryType == type) candidate,
    ]..sort((a, b) => (b.difficulty ?? 0) - (a.difficulty ?? 0));
    return matching.length > limit ? matching.sublist(0, limit) : matching;
  }

  /// 合并后的推荐词：先并集各批的 `recommendedTerms`，再剔除已被截断的词；
  /// 一个都不剩时回退本地推荐。
  List<String> _mergedRecommendedTerms(
    List<ArticleImportPreview> previews,
    List<ArticleCandidate> merged,
  ) {
    final surviving = <String>{
      for (final candidate in merged)
        if (candidate.entryType == LexicalContentType.word)
          candidate.normalizedTerm.toLowerCase(),
    };
    final terms = <String>{};
    for (final preview in previews) {
      for (final term in preview.recommendedTerms) {
        final lower = term.toLowerCase();
        if (surviving.contains(lower)) terms.add(lower);
      }
    }
    if (terms.isNotEmpty) return terms.toList(growable: false);
    return fallbackRecommendedTerms(merged);
  }

  ArticleStats _mergedStats(
    List<ArticleImportPreview> previews,
    List<ArticleCandidate> merged,
  ) {
    final wordCount = previews.fold(
      0,
      (sum, preview) => sum + preview.articleStats.wordCount,
    );
    final charCount = previews.fold(
      0,
      (sum, preview) => sum + preview.articleStats.charCount,
    );
    final wordCandidates = merged
        .where((candidate) => candidate.entryType == LexicalContentType.word)
        .length;
    final uniqueCount = wordCandidates > 0 ? wordCandidates : merged.length;
    return ArticleStats(
      charCount: charCount,
      wordCount: wordCount > 0
          ? wordCount
          : uniqueCount * articleWordCountEstimateFactor,
      uniqueCount: uniqueCount,
      knownCount: merged.where((candidate) => candidate.isKnown).length,
      unknownCount: merged.where((candidate) => candidate.isCandidate).length,
      phraseCount: merged
          .where(
            (candidate) => candidate.entryType == LexicalContentType.phrase,
          )
          .length,
      sentenceCount: merged
          .where(
            (candidate) => candidate.entryType == LexicalContentType.sentence,
          )
          .length,
    );
  }

  // ── 提交内部实现 ──

  List<ArticleCandidate> _selectedCandidates(
    ArticleImportPreview preview,
    Set<String> selectedKeys,
  ) {
    final keys = <String>{
      for (final key in selectedKeys)
        if (key.trim().isNotEmpty) articleNormalizedLookupKey(key.trim()),
    };
    if (keys.isEmpty) return const <ArticleCandidate>[];
    return <ArticleCandidate>[
      for (final candidate in preview.candidates)
        if (keys.contains(articleSelectionKey(candidate).toLowerCase()) ||
            keys.contains(articleNormalizedLookupKey(candidate.normalizedTerm)))
          candidate,
    ];
  }

  Future<void> _commitCandidate(
    ArticleCandidate candidate,
    _CommitOptions options,
    _CommitCounters counters,
  ) async {
    try {
      final wordId = await _words.create(
        draft: _draftFor(candidate, options),
        now: options.now,
      );
      counters.created += 1;
      counters.createdWordIds.add(wordId);
      counters.affectedWordIds.add(wordId);
      await _words.enqueueInitialization(
        wordId: wordId,
        now: options.now,
        mode: InitializationMode.skipInitialized,
        priority: jobPriorityNewWord,
        requestedProviders: options.dictionaryProviders,
      );
      await _words.markInitializationQueuedIfNoDefinition(
        wordId: wordId,
        now: options.now,
      );
      counters.queued += 1;
    } on ConflictError catch (error) {
      if (error.code != AppErrorCode.termAlreadyExists) rethrow;
      counters.existing += 1;
      await _enqueueExisting(candidate, options, counters);
    }
  }

  /// 已有词条按导入模式入队。
  Future<void> _enqueueExisting(
    ArticleCandidate candidate,
    _CommitOptions options,
    _CommitCounters counters,
  ) async {
    final initializationMode = switch (options.mode) {
      ImportMode.skipExisting => null,
      ImportMode.fillMissing => InitializationMode.fillMissingFields,
      ImportMode.forceDictionaryRefresh => InitializationMode.forceOverwrite,
    };
    final wordId = await _words.findByTerm(
      term: candidate.term,
      sourceLanguage: options.preview.sourceLanguage,
      targetLanguage: options.preview.targetLanguage,
    );
    if (wordId == null) return;
    if (options.resetAt != null) {
      await resetLearningProgressNow(
        db: _db,
        wordId: wordId,
        now: options.resetAt!,
      );
    }
    if (initializationMode == null) return;
    counters.affectedWordIds.add(wordId);
    await _words.enqueueInitialization(
      wordId: wordId,
      now: options.now,
      mode: initializationMode,
      priority: options.mode == ImportMode.forceDictionaryRefresh
          ? jobPriorityForceOverwrite
          : jobPriorityFillMissing,
      requestedProviders: options.dictionaryProviders,
    );
    await _words.markInitializationQueuedIfNoDefinition(
      wordId: wordId,
      now: options.now,
    );
  }

  /// 词条草稿：保留原文出处例句（可选）与批次标签，单词释义留空交由有道查词补全。
  WordDraft _draftFor(ArticleCandidate candidate, _CommitOptions options) {
    final sourceSentence = candidate.sourceSentence?.trim() ?? '';
    final examples =
        options.includeSourceSentence &&
            sourceSentence.isNotEmpty &&
            candidate.entryType != LexicalContentType.sentence
        ? <WordExampleDraft>[
            WordExampleDraft(
              sentence: sourceSentence,
              source: 'article',
              isUserAdded: true,
            ),
          ]
        : const <WordExampleDraft>[];
    return WordDraft(
      term: candidate.term,
      contentType: candidate.entryType,
      sourceLanguage: options.preview.sourceLanguage,
      targetLanguage: options.preview.targetLanguage,
      definitions: _definitionsFor(candidate),
      examples: examples,
      tags: options.tags,
    );
  }

  List<String>? _dictionaryProvidersFor(AppSettings settings) {
    final p = settings.providers;
    final enabled = <String>[
      if (p.youdaoEnabled) 'youdao',
      if (p.icibaEnabled) 'iciba',
      if (p.merriamWebsterEnabled) 'merriam-webster',
      if (p.dictionaryApiEnabled) 'dictionaryapi.dev',
      if (p.myMemoryEnabled) 'mymemory',
    ];
    final ordered = <String>[
      for (final id in defaultTranslationProviderOrder)
        if (enabled.contains(id)) id,
    ];
    return ordered.isEmpty ? null : ordered;
  }

  List<String> _cleanTags(List<String> tags) {
    final out = <String>[];
    for (final raw in tags) {
      final tag = raw.trim();
      if (tag.isNotEmpty && !out.contains(tag)) out.add(tag);
    }
    return List<String>.unmodifiable(out);
  }

  List<String> _definitionsFor(ArticleCandidate candidate) {
    final card = candidate.aiCard;
    if (card == null) return const <String>[];
    final free = card.freeTranslation.trim();
    final text = free.isNotEmpty ? free : card.literalTranslation.trim();
    return text.isEmpty ? const <String>[] : <String>[text];
  }

  // ── 预览存储 ──

  ArticleImportPreview _store(ArticleImportPreview preview, int now) {
    _purgeExpired(now);
    _previews[preview.previewToken] = preview;
    return preview;
  }

  void _purgeExpired(int now) =>
      _previews.removeWhere((_, preview) => preview.expiresAt <= now);

  String _newToken() {
    final random = math.Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < articlePreviewTokenLength; index += 1) {
      buffer.write(_tokenAlphabet[random.nextInt(_tokenAlphabet.length)]);
    }
    return buffer.toString();
  }

  // ── 小工具 ──

  List<String> _candidateTerms(List<ArticleCandidate> candidates) => <String>[
    for (final candidate in candidates)
      if (candidate.isCandidate) candidate.normalizedTerm.toLowerCase(),
  ];

  List<ArticlePromptCandidate> _aiCandidates(
    List<ArticleCandidate> candidates,
  ) {
    final out = <ArticlePromptCandidate>[];
    for (final candidate in candidates) {
      if (!candidate.isCandidate) continue;
      out.add(
        ArticlePromptCandidate(
          term: candidate.term,
          normalizedTerm: candidate.normalizedTerm,
          occurrences: candidate.occurrences,
          sourceSentence: candidate.sourceSentence,
        ),
      );
      if (out.length >= articleAiCandidateLimit) break;
    }
    return out;
  }

  String _aiArticleText(String cleaned, List<String> sentences) {
    final snippet = cleaned.length > articleSnippetChars
        ? cleaned.substring(0, articleSnippetChars)
        : cleaned;
    if (sentences.isEmpty) return snippet;
    final head = sentences
        .take(articleAiSnippetSentenceLimit)
        .toList(growable: false);
    return '$snippet\n\n<sentences>${jsonEncode(head)}</sentences>';
  }

  String? _sentenceFor(String term, List<String> sentences) {
    final lower = term.toLowerCase();
    for (final sentence in sentences) {
      if (sentence.toLowerCase().contains(lower)) return sentence;
    }
    return null;
  }

  String _shortToken(String token) => token.length > articleShortTokenChars
      ? token.substring(0, articleShortTokenChars)
      : token;
}

/// 把文章导入的错误转成面向用户的中文说明。
///
/// **与旧版的差异（有意）**：旧版把服务端的 `文章参数无效。` 原样展示，
/// 用户看到「参数无效」既不知道哪一段有问题、也不知道该怎么办。
/// `core/errors.dart` 已冻结（不允许新增错误码），所以按错误码给出可操作
/// 说明的映射留在本模块；界面层与分段失败共用这一处，避免两处文案漂移。
String articleImportErrorMessage(AppError error) => switch (error.code) {
  AppErrorCode.validationError =>
    '这段文字不满足分析要求：至少 $minArticleChars 个字符，且需包含英文单词。',
  AppErrorCode.importPreviewExpired => '预览已过期，请重新分析这篇文章。',
  _ => error.message,
};

/// 预览令牌的字符表。
///
/// 旧版用 `crypto.randomUUID()`；Dart 侧没有内置 UUID，用等长的
/// 随机十六进制串即可——令牌只在本进程内做 Map 键，不需要全局唯一性。
const String _tokenAlphabet = '0123456789abcdef';

/// 一次预览的公共上下文。
class _PreviewContext {
  const new({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.existing,
    required this.sentences,
    required this.examTargets,
    required this.difficultyMode,
    required this.extractScope,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final List<_ExistingTerm> existing;
  final List<String> sentences;
  final List<VocabularyLevel> examTargets;
  final ArticleDifficultyMode difficultyMode;
  final ArticleExtractScope extractScope;
}

/// 分段并发预览的公共参数。
class _SegmentOptions {
  const new({
    required this.examTargets,
    required this.difficultyMode,
    required this.extractScope,
    required this.now,
  });

  final List<VocabularyLevel>? examTargets;
  final ArticleDifficultyMode difficultyMode;
  final ArticleExtractScope extractScope;
  final int now;
}

/// 提交选项。
class _CommitOptions {
  const new({
    required this.preview,
    required this.mode,
    required this.now,
    required this.resetAt,
    required this.includeSourceSentence,
    required this.tags,
    required this.dictionaryProviders,
  });

  final ArticleImportPreview preview;
  final ImportMode mode;
  final int now;
  final int? resetAt;
  final bool includeSourceSentence;
  final List<String> tags;
  final List<String>? dictionaryProviders;
}

/// 一条已有词条（只取判定 KNOWN 需要的两列）。
class _ExistingTerm {
  const new({required this.normalizedTerm, required this.contentType});

  final String normalizedTerm;
  final LexicalContentType contentType;
}

/// AI 选词合回候选后的结果。
class _AiOutcome {
  const new({
    required this.candidates,
    required this.recommendedTerms,
    required this.aiApplied,
    this.aiError,
  });

  final List<ArticleCandidate> candidates;
  final List<String> recommendedTerms;
  final bool aiApplied;
  final String? aiError;
}

/// 提交过程的计数器。
class _CommitCounters {
  int created = 0;
  int existing = 0;
  int queued = 0;
  final List<int> createdWordIds = <int>[];
  final List<int> affectedWordIds = <int>[];
}
