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
        examTargets: examTargets,
        now: now,
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
    final resetAt = resetAtFor(
      mode,
      requested: resetLearningProgress,
      now: now,
    );
    final counters = _CommitCounters();
    for (final candidate in selected) {
      await _commitCandidate(candidate, preview, mode, counters, now, resetAt);
    }
    return ArticleCommitResult(
      createdWords: counters.created,
      existingWords: counters.existing,
      queuedInitializations: counters.queued,
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
  }) async {
    final settings = await _settings.load();
    return _PreviewContext(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      existing: await _existingTerms(sourceLanguage, targetLanguage),
      sentences: _candidateSentences(cleaned),
      // 旧版 `settings.examTargets ?? (vocabularyLevel !== AUTO ? [level] : [])`
      // 的回退分支不可达：设置层保证 `examTargets` 恒为数组。
      examTargets: examTargets ?? settings.examTargets,
    );
  }

  /// 该语言方向下的全部已有词条（归一化词形 + 内容类型）。
  ///
  /// 一次读回而不是逐词查：旧版 `createArticlePreview` 也是整表读一次，
  /// 逐词查会让 200 个候选产生 200 次查询。
  Future<List<_ExistingTerm>> _existingTerms(
    String sourceLanguage,
    String targetLanguage,
  ) async {
    final query = _db.select(_db.words)
      ..where(
        (table) =>
            table.sourceLanguage.equals(sourceLanguage) &
            table.targetLanguage.equals(targetLanguage),
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
      fallbackTerms: fallbackTerms,
    );
  }

  _AiOutcome _mergeAiResult({
    required List<ArticleCandidate> candidates,
    required ArticleAiSelection result,
    required _PreviewContext context,
    required List<String> fallbackTerms,
  }) {
    final byTerm = <String, ArticleAiWord>{
      for (final word in result.words)
        articleNormalizedLookupKey(word.term): word,
    };
    final withMeta = <ArticleCandidate>[
      for (final candidate in candidates)
        _withAiMeta(
          candidate,
          byTerm[articleNormalizedLookupKey(candidate.term)],
        ),
    ];
    final selected = <String>{
      for (final word in result.words) articleNormalizedLookupKey(word.term),
    };
    final recommended = result.words.isEmpty
        ? fallbackTerms
        : <String>[
            for (final candidate in withMeta)
              if (selected.contains(
                articleNormalizedLookupKey(candidate.normalizedTerm),
              ))
                candidate.normalizedTerm.toLowerCase(),
          ];
    final merged = <ArticleCandidate>[
      ...withMeta,
      ..._aiPhraseCandidates(result, context, withMeta),
      ..._aiSentenceCandidates(result, context, withMeta),
    ];
    return _AiOutcome(
      candidates: merged,
      recommendedTerms: recommended,
      aiApplied: result.hasContent,
      aiError: result.error,
    );
  }

  /// 把 AI 的单词元数据（理由 / 难度 / CEFR / 词频）写回候选。
  ///
  /// 旧版先按 `term.toLowerCase()` 匹配，再按 NFKC 归一化后的词形匹配——
  /// 两套键都要试，否则「AI 返回 `Apple`、候选是 `apple`」这类大小写差异
  /// 会让元数据整体丢失。
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
      aiReason: meta.reason,
      difficulty: meta.difficulty,
      cefrLevel: meta.cefrLevel,
      frequency: meta.frequency,
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
    required List<VocabularyLevel>? examTargets,
    required int now,
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
        controller.add(
          await _runBatch(plan.batches[index], texts, examTargets, now),
        );
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
    List<VocabularyLevel>? examTargets,
    int now,
  ) async {
    try {
      final combined = <String>[
        for (final id in batch.segmentIds) texts[id] ?? '',
      ].join(articleParagraphSeparator);
      return ArticleSegmentOutcome.success(
        batchIndex: batch.batchIndex,
        preview: await preview(
          articleText: combined,
          examTargets: examTargets,
          now: now,
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
    ArticleImportPreview preview,
    ImportMode mode,
    _CommitCounters counters,
    int now,
    int? resetAt,
  ) async {
    try {
      final wordId = await _words.create(
        draft: _draftFor(candidate, preview),
        now: now,
      );
      counters.created += 1;
      await _words.enqueueInitialization(
        wordId: wordId,
        now: now,
        // 旧版新词条用 `SKIP_INITIALIZED` + 优先级 10：新建词条通常没有内容，
        // 「已有内容则跳过」等价于「全部补全」，而优先级要压过其他自动任务。
        mode: InitializationMode.skipInitialized,
        priority: jobPriorityNewWord,
      );
      // 旧版 `commitImport` 入队后还会 `markWordInitializationQueued`：
      // 新词条的初始状态是 `PENDING`（还没排队），入队成功却不改状态的话，
      // 词库页按状态筛选时这批词条会一直显示成「待初始化」。
      await _words.markInitializationQueuedIfNoDefinition(
        wordId: wordId,
        now: now,
      );
      counters.queued += 1;
    } on ConflictError catch (error) {
      if (error.code != AppErrorCode.termAlreadyExists) rethrow;
      counters.existing += 1;
      await _enqueueExisting(candidate, preview, mode, now, resetAt);
    }
  }

  /// 已有词条按导入模式入队。
  ///
  /// 语义与旧版 `commitImport` 一致：活跃任务按强弱升级、优先级只升不降
  /// （`WordEditService.enqueueInitialization` 负责），入队后把无释义词条
  /// 标成 `QUEUED`（`markInitializationQueuedIfNoDefinition`）。
  ///
  /// **这里的入队不计入 `queuedInitializations`**：插入是否真的发生不可观测，
  /// 而对已有词条来说「已存在活跃任务」是常态，计进去只会让界面报出一个
  /// 并不存在的数字。旧版是拿 `enqueueJob` 的返回值计数的，本版没有等价
  /// 返回值——宁可少报，也不报一个假的。
  Future<void> _enqueueExisting(
    ArticleCandidate candidate,
    ArticleImportPreview preview,
    ImportMode mode,
    int now,
    int? resetAt,
  ) async {
    final initializationMode = switch (mode) {
      ImportMode.skipExisting => null,
      ImportMode.fillMissing => InitializationMode.fillMissingFields,
      ImportMode.forceDictionaryRefresh => InitializationMode.forceOverwrite,
    };
    final wordId = await _words.findByTerm(
      term: candidate.term,
      sourceLanguage: preview.sourceLanguage,
      targetLanguage: preview.targetLanguage,
    );
    if (wordId == null) return;
    // 重置学习进度与「是否入队」无关：旧版在 `SKIP_EXISTING` 之外的任何
    // 模式、以及任何命中已有词条的行上都会执行它。所以这一步必须放在
    // `initializationMode == null` 的提前返回**之前**。
    if (resetAt != null) {
      await resetLearningProgressNow(db: _db, wordId: wordId, now: resetAt);
    }
    if (initializationMode == null) return;
    await _words.enqueueInitialization(
      wordId: wordId,
      now: now,
      mode: initializationMode,
      priority: mode == ImportMode.forceDictionaryRefresh
          ? jobPriorityForceOverwrite
          : jobPriorityFillMissing,
    );
    await _words.markInitializationQueuedIfNoDefinition(
      wordId: wordId,
      now: now,
    );
  }

  /// 词条草稿。
  ///
  /// **与旧版的差异（有意）**：旧版只写 `words` 行、把 AI 卡片留在
  /// `import_rows.raw_json` 里，结果短语与句子永远等不到内容——词典 provider
  /// 给不出句子的释义，词条会一直停在 `PENDING`，进不了学习队列。
  /// 本版把 AI 卡片的意译（缺失时用直译）作为初始释义写入，使导入的短语与
  /// 句子立刻可用；单词没有 AI 释义，仍然保持空释义交给初始化队列。
  WordDraft _draftFor(
    ArticleCandidate candidate,
    ArticleImportPreview preview,
  ) => WordDraft(
    term: candidate.term,
    contentType: candidate.entryType,
    sourceLanguage: preview.sourceLanguage,
    targetLanguage: preview.targetLanguage,
    definitions: _definitionsFor(candidate),
  );

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
  });

  final String sourceLanguage;
  final String targetLanguage;
  final List<_ExistingTerm> existing;
  final List<String> sentences;
  final List<VocabularyLevel> examTargets;
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
}
