/// 文章导入服务的集成测试。
///
/// 钉住的性质：KNOWN/CANDIDATE 判定（内容类型 + 归一化词形）、候选与
/// 送 AI 候选的上限、**AI 失败 / 未配置时回退本地筛选并带出原因**、
/// 分段预览的并发上限与批边界、合并的令牌去重与按库重判、提交的幂等
/// （重复提交不建重复词条）与初始化任务入队。
///
/// 全部 LLM 调用由 [_FakeSelector] 顶替，**不发真实网络请求**。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/import/content_type.dart';
import 'package:lexiloop/domain/article_import/article_ai_models.dart';
import 'package:lexiloop/domain/article_import/article_candidates.dart';
import 'package:lexiloop/domain/article_import/article_models.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/services/article_import/article_ai_selector.dart';
import 'package:lexiloop/services/article_import/article_import_service.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/word_edit_service.dart';

/// 假 AI 选词器：记录输入、统计并发、按预设返回结果。
class _FakeSelector implements ArticleAiSelector {
  new(this._handler);

  final Future<ArticleAiSelection> Function(ArticleAiSelectInput input)
  _handler;

  /// 依次收到的输入。
  final List<ArticleAiSelectInput> calls = <ArticleAiSelectInput>[];

  /// 当前在飞请求数。
  int inFlight = 0;

  /// 观察到的最大并发数。
  int maxInFlight = 0;

  @override
  Future<ArticleAiSelection> select(ArticleAiSelectInput input) async {
    calls.add(input);
    inFlight += 1;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      return await _handler(input);
    } finally {
      inFlight -= 1;
    }
  }
}

/// 默认返回「AI 没有结果也没报错」的选词器。
_FakeSelector _noneSelector() =>
    _FakeSelector((_) async => ArticleAiSelection.none);

/// 造一个 4 字母的英文词（保证互不相同且不在停用词表里）。
String wordAt(int index) {
  const letters = 'abcdefghijklmnopqrstuvwxyz';
  var value = index;
  final buffer = StringBuffer('z');
  for (var digit = 0; digit < 3; digit += 1) {
    buffer.write(letters[value % 26]);
    value ~/= 26;
  }
  return buffer.toString();
}

/// 一段长度足够的样例文章。
const String sampleArticle =
    'The rapid advancement of artificial intelligence has profoundly reshaped '
    'how we acquire knowledge. Contemporary cognitive science suggests that '
    'contextual learning yields durable retention.';

void main() {
  late AppDatabase db;
  late SettingsService settings;
  late WordEditService words;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    settings = SettingsService(SettingsDao(db));
    words = WordEditService(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  ArticleImportService serviceWith(ArticleAiSelector selector) =>
      ArticleImportService(db, settings, words, selector);

  Future<int> insertWord({
    required String term,
    String? normalizedTerm,
    LexicalContentType contentType = LexicalContentType.word,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: normalizedTerm ?? term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh-CN',
            entryType: entryTypeFor(contentType),
            contentType: Value<LexicalContentType>(contentType),
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(wordId: Value<int>(id), updatedAt: now),
        );
    return id;
  }

  Future<List<WordRow>> allWords() => db.select(db.words).get();

  Future<List<InitializationJobRow>> allJobs() =>
      db.select(db.initializationJobs).get();

  ArticleCandidate candidateOf(
    ArticleImportPreview preview,
    String term, {
    LexicalContentType entryType = LexicalContentType.word,
  }) => preview.candidates.firstWhere(
    (candidate) =>
        candidate.entryType == entryType &&
        candidate.normalizedTerm == term.toLowerCase(),
  );

  group('预览', () {
    test('按内容类型与归一化词形判定 KNOWN', () async {
      await insertWord(term: 'Knowledge');
      // 同名词形但类型是短语：不应把单词候选判为已掌握。
      await insertWord(term: 'acquire', contentType: LexicalContentType.phrase);
      final service = serviceWith(_noneSelector());

      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      expect(
        candidateOf(preview, 'knowledge').status,
        ArticleCandidateStatus.known,
      );
      expect(
        candidateOf(preview, 'acquire').status,
        ArticleCandidateStatus.candidate,
      );
      expect(preview.knownCount, 1);
      expect(preview.articleStats.knownCount, 1);
    });

    test('单词候选截到上限，但去重词数按未截断的总数统计', () async {
      final article = <String>[
        for (var index = 0; index < maxArticleCandidates + 50; index += 1)
          wordAt(index),
      ].join(' ');
      final service = serviceWith(_noneSelector());

      final preview = await service.preview(articleText: article, now: now);

      expect(preview.candidates.length, maxArticleCandidates);
      expect(preview.articleStats.uniqueCount, maxArticleCandidates + 50);
      expect(preview.articleStats.wordCount, maxArticleCandidates + 50);
    });

    test('AI 未配置时回退本地筛选并把原因带出', () async {
      final service = serviceWith(
        _FakeSelector(
          (_) async => const ArticleAiSelection.failure(
            errorCode: AppErrorCode.aiDisabled,
            error: 'AI 未启用，请到设置页开启 AI。',
          ),
        ),
      );

      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      expect(preview.aiApplied, isFalse);
      expect(preview.aiError, 'AI 未启用，请到设置页开启 AI。');
      // 回退不是「没选中任何词」：本地候选与推荐词都要在。
      expect(preview.candidates, isNotEmpty);
      expect(preview.recommendedTerms, isNotEmpty);
      expect(preview.recommendedKeys, isNotEmpty);
    });

    test('AI 返回格式无效时回退并带出原因', () async {
      final service = serviceWith(
        _FakeSelector(
          (_) async => const ArticleAiSelection.failure(
            errorCode: AppErrorCode.aiResponseInvalid,
            error: 'AI 返回格式不符合预期，已回退为本地筛选。',
          ),
        ),
      );

      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      expect(preview.aiApplied, isFalse);
      expect(preview.aiError, contains('已回退为本地筛选'));
      expect(preview.recommendedTerms, isNotEmpty);
    });

    test('送 AI 的候选只含待学项且不超过上限', () async {
      await insertWord(term: 'knowledge');
      final selector = _noneSelector();
      final service = serviceWith(selector);

      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      final sent = selector.calls.single.candidates;
      expect(sent.length, preview.candidateCount);
      expect(sent.any((item) => item.normalizedTerm == 'knowledge'), isFalse);
      expect(selector.calls.single.totalKnown, 1);
      expect(selector.calls.single.examTargets, isEmpty);
    });

    test('考试目标按入参优先，缺省时用设置', () async {
      final selector = _noneSelector();
      final service = serviceWith(selector);

      await service.preview(
        articleText: sampleArticle,
        examTargets: <VocabularyLevel>[VocabularyLevel.cet6],
        now: now,
      );

      expect(selector.calls.single.examTargets, <VocabularyLevel>[
        VocabularyLevel.cet6,
      ]);
    });

    test('AI 成功时写入词元数据、推荐词，并追加短语与句子候选', () async {
      final service = serviceWith(
        _FakeSelector(
          (_) async => const ArticleAiSelection.success(
            words: <ArticleAiWord>[
              ArticleAiWord(
                term: 'knowledge',
                reason: '学术词',
                difficulty: 4,
                cefrLevel: 'B2',
                frequency: 'NORMAL',
              ),
            ],
            phrases: <ArticleAiPhrase>[
              ArticleAiPhrase(
                term: 'cognitive science',
                reason: '固定搭配',
                difficulty: 3,
                literalTranslation: '认知科学',
                freeTranslation: '认知科学',
              ),
            ],
            sentences: <ArticleAiSentence>[
              ArticleAiSentence(
                sentence:
                    'Contemporary cognitive science suggests that contextual '
                    'learning yields durable retention.',
                literalTranslation: '当代认知科学表明情境学习产生持久记忆。',
                freeTranslation: '当代认知科学认为，在语境中学更记得住。',
              ),
            ],
          ),
        ),
      );

      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      expect(preview.aiApplied, isTrue);
      expect(preview.aiError, isNull);
      final word = candidateOf(preview, 'knowledge');
      expect(word.aiReason, '学术词');
      expect(word.difficulty, 4);
      expect(word.cefrLevel, 'B2');
      expect(word.frequency, 'NORMAL');
      expect(preview.recommendedTerms, <String>['knowledge']);
      expect(
        preview.recommendedKeys,
        contains(articleCandidateKey(LexicalContentType.word, 'knowledge')),
      );

      final phrase = candidateOf(
        preview,
        'cognitive science',
        entryType: LexicalContentType.phrase,
      );
      expect(phrase.aiCard?.freeTranslation, '认知科学');
      expect(phrase.sourceSentence, isNotNull);
      expect(preview.articleStats.phraseCount, 1);
      expect(preview.articleStats.sentenceCount, 1);
      expect(
        preview.recommendedKeys,
        contains(
          articleCandidateKey(LexicalContentType.phrase, 'cognitive science'),
        ),
      );
      expect(
        preview.recommendedKeys,
        contains(
          articleCandidateKey(
            LexicalContentType.sentence,
            'contemporary cognitive science suggests that contextual learning '
            'yields durable retention.',
          ),
        ),
      );
    });

    test('AI 短语按上限截断，重复项与已有词条被跳过', () async {
      await insertWord(
        term: 'existing phrase',
        contentType: LexicalContentType.phrase,
      );
      final service = serviceWith(
        _FakeSelector(
          (_) async => ArticleAiSelection.success(
            phrases: <ArticleAiPhrase>[
              const ArticleAiPhrase(
                term: 'existing phrase',
                reason: '已在词库',
                difficulty: 2,
                literalTranslation: '已有',
                freeTranslation: '已有',
              ),
              const ArticleAiPhrase(
                term: 'duplicated',
                reason: '重复',
                difficulty: 2,
                literalTranslation: '重复',
                freeTranslation: '重复',
              ),
              const ArticleAiPhrase(
                term: 'duplicated',
                reason: '重复',
                difficulty: 2,
                literalTranslation: '重复',
                freeTranslation: '重复',
              ),
              for (var index = 0; index < articleAiPhrasesMaxItems; index += 1)
                ArticleAiPhrase(
                  term: 'phrase ${wordAt(index)}',
                  reason: '待学',
                  difficulty: 1,
                  literalTranslation: '直译',
                  freeTranslation: '意译',
                ),
            ],
          ),
        ),
      );

      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      // 旧版先按上限截断 AI 列表、再逐条跳过重复与已有词条，因此
      // 「已有 1 条 + 重复 1 条」会从配额里占掉两个位置：15 - 2 = 13。
      expect(preview.articleStats.phraseCount, articlePhraseLimit - 2);
      expect(
        preview.candidates.where(
          (candidate) => candidate.normalizedTerm == 'existing phrase',
        ),
        isEmpty,
      );
      expect(
        preview.candidates
            .where((candidate) => candidate.normalizedTerm == 'duplicated')
            .length,
        1,
      );
    });

    test('文章过短、过长或提不出单词时报校验错误', () async {
      final service = serviceWith(_noneSelector());

      await expectLater(
        service.preview(articleText: 'too short', now: now),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.details,
            'details',
            contains('至少'),
          ),
        ),
      );
      await expectLater(
        service.preview(articleText: 'a' * (maxArticleChars + 1), now: now),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.details,
            'details',
            contains('不能超过'),
          ),
        ),
      );
      await expectLater(
        service.preview(articleText: '1234567890123456789012345', now: now),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.details,
            'details',
            contains('未能从文章中提取到有效单词'),
          ),
        ),
      );
    });
  });

  group('分段预览', () {
    String paragraphs(List<String> texts) => texts.join('\n\n');

    test('按批并发，并发数不超过上限', () async {
      final article = paragraphs(<String>[
        for (var index = 0; index < 6; index += 1) '${wordAt(index)} ' * 20,
      ]);
      final selector = _FakeSelector((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return ArticleAiSelection.none;
      });
      final service = serviceWith(selector);

      final outcomes = await service
          .previewSegments(articleText: article, segmentsPerBatch: 1, now: now)
          .toList();

      expect(outcomes.length, 6);
      expect(outcomes.every((outcome) => outcome.isSuccess), isTrue);
      expect(outcomes.map((outcome) => outcome.batchIndex).toSet(), <int>{
        0,
        1,
        2,
        3,
        4,
        5,
      });
      expect(selector.maxInFlight, articleSegmentConcurrency);
    });

    test('每批多段时批次数量按分段数折算', () async {
      final article = paragraphs(<String>[
        for (var index = 0; index < 5; index += 1) '${wordAt(index)} ' * 20,
      ]);
      final service = serviceWith(_noneSelector());

      final outcomes = await service
          .previewSegments(articleText: article, segmentsPerBatch: 2, now: now)
          .toList();

      expect(outcomes.length, 3);
    });

    test('单批失败不影响其他批，失败原因挂在该批上', () async {
      final article = paragraphs(<String>[
        '${wordAt(1)} ' * 20,
        'tiny',
        '${wordAt(2)} ' * 20,
      ]);
      final service = serviceWith(_noneSelector());

      final outcomes = await service
          .previewSegments(articleText: article, segmentsPerBatch: 1, now: now)
          .toList();

      final failed = outcomes.where((outcome) => !outcome.isSuccess).toList();
      expect(failed.length, 1);
      expect(failed.single.error, contains('至少'));
      expect(outcomes.where((outcome) => outcome.isSuccess).length, 2);
    });
  });

  group('合并', () {
    test('按令牌去重，并按当前词库重新判定 KNOWN', () async {
      final service = serviceWith(_noneSelector());
      final first = await service.preview(articleText: sampleArticle, now: now);
      final second = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      // 预览之后词条才被建出来：合并时必须重新判定。
      await insertWord(term: 'knowledge');

      final merged = await service.mergePreviews(
        tokens: <String>[first.previewToken, second.previewToken],
        now: now,
      );

      expect(merged.previewToken, isNot(first.previewToken));
      expect(merged.knownCount, greaterThanOrEqualTo(1));
      expect(
        candidateOf(merged, 'knowledge').status,
        ArticleCandidateStatus.known,
      );
      // 同一个令牌重复传入只算一次。
      final deduped = await service.mergePreviews(
        tokens: <String>[first.previewToken, first.previewToken],
        now: now,
      );
      expect(
        candidateOf(deduped, 'rapid').occurrences,
        candidateOf(first, 'rapid').occurrences,
      );
    });

    test('合并结果的有效期重新计算，令牌不存在时报过期', () async {
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      final merged = await service.mergePreviews(
        tokens: <String>[preview.previewToken],
        now: now,
      );
      expect(merged.expiresAt, now + importPreviewTtlMs);

      await expectLater(
        service.mergePreviews(tokens: <String>['missing'], now: now),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importPreviewExpired,
          ),
        ),
      );
    });

    test('过期的预览不可合并', () async {
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      await expectLater(
        service.mergePreviews(
          tokens: <String>[preview.previewToken],
          now: now + importPreviewTtlMs + 1,
        ),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importPreviewExpired,
          ),
        ),
      );
    });

    test('空令牌列表报参数错误', () async {
      final service = serviceWith(_noneSelector());
      await expectLater(
        service.mergePreviews(tokens: const <String>[], now: now),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.validationError,
          ),
        ),
      );
    });
  });

  group('提交', () {
    test('新建词条并为每个新词条入队初始化任务', () async {
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      final selected = preview.recommendedKeys.toSet();

      final result = await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: selected,
        mode: ImportMode.skipExisting,
        now: now,
      );

      expect(result.createdWords, selected.length);
      expect(result.existingWords, 0);
      expect(result.queuedInitializations, result.createdWords);
      expect((await allWords()).length, result.createdWords);
      final jobs = await allJobs();
      expect(jobs.length, result.createdWords);
      expect(
        jobs.every((job) => job.mode == InitializationMode.skipInitialized),
        isTrue,
      );
      expect(
        jobs.every((job) => job.taskType == JobTaskType.initialize),
        isTrue,
      );
      expect(jobs.every((job) => job.priority == jobPriorityNewWord), isTrue);
    });

    test('新建的无释义词条在入队后状态为 QUEUED', () async {
      // 旧版 `commitImport` 在入队后调 `markWordInitializationQueued`：
      // 没有这一步，这批词条会停在 PENDING，词库页按状态筛选时
      // 「待初始化」里会一直躺着一批其实已经在队列里的词条。
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: preview.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );

      final words = await allWords();
      expect(words, isNotEmpty);
      expect(
        words.every(
          (word) => word.initializationStatus == InitializationStatus.queued,
        ),
        isTrue,
        reason: '新词条没有释义，入队后应当标成 QUEUED',
      );
    });

    test('已有释义的词条入队后不会被压回 QUEUED', () async {
      // 反向用例：状态同时表达「内容完整度」，已有释义的词条被压回 QUEUED
      // 会让详情页显示成「还没初始化」，而它明明已经能出题。
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: preview.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );
      final wordId = (await allWords()).first.id;
      // `create` 未必为该词条建内容行（文章导入的单词把释义留给初始化队列），
      // 所以这里用 upsert 而不是 update：update 命中 0 行时测试会假绿。
      await db
          .into(db.wordContents)
          .insertOnConflictUpdate(
            WordContentsCompanion.insert(
              wordId: Value<int>(wordId),
              updatedAt: now,
              definitionsJson: const Value<String>(
                '[{"language":"zh-CN","text":"已有的释义"}]',
              ),
            ),
          );

      // 先把它置成「内容完整度」状态（提交后它是 QUEUED），
      // 这样断言「方法没动它」才有意义——否则它本来就已经是 QUEUED。
      await (db.update(db.words)..where((row) => row.id.equals(wordId))).write(
        const WordsCompanion(
          initializationStatus: Value<InitializationStatus>(
            InitializationStatus.partial,
          ),
        ),
      );

      await WordEditService(db)
          .markInitializationQueuedIfNoDefinition(wordId: wordId, now: now);

      final word = (await allWords()).firstWhere((row) => row.id == wordId);
      expect(
        word.initializationStatus,
        InitializationStatus.partial,
        reason: '已有释义的词条状态不该被改成 QUEUED',
      );
    });

    test('勾选重置学习进度时，命中的已有词条复习历史被清空', () async {
      // 旧版 `article-tab.tsx:475,526` 的「重置本次已有词条的学习进度」。
      // 重置是不可逆的删历史，所以必须有一条用例钉住它真的发生了。
      final service = serviceWith(_noneSelector());
      // 两次预览都要在第一次提交之前取：提交之后候选都成了 KNOWN，
      // 第二次预览的 recommendedKeys 会是空的，提交会直接报校验错误。
      final first = await service.preview(articleText: sampleArticle, now: now);
      final second = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      await service.commit(
        previewToken: first.previewToken,
        selectedKeys: first.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );
      final wordId = (await allWords()).first.id;
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              clientAnswerId: 'answer-before-reset',
              wordId: wordId,
              reviewedAt: now,
              rating: ReviewRating.again,
              questionType: QuestionType.enToZh,
              isCorrect: false,
              createdAt: now,
            ),
          );
      await db
          .into(db.wordReviewStats)
          .insert(
            WordReviewStatsCompanion.insert(
              wordId: Value<int>(wordId),
              totalReviews: const Value<int>(1),
              correctReviews: const Value<int>(0),
              updatedAt: Value<int>(now),
            ),
          );
      expect(
        await (db.select(
          db.reviewLogs,
        )..where((row) => row.wordId.equals(wordId))).get(),
        hasLength(1),
      );

      // 用 `FILL_MISSING` 而不是 `SKIP_EXISTING`：本版（与 CSV 路径一致）
      // 约定「仅新增」模式下勾了重置也不动已有词条——那批词条根本没参与
      // 本次导入，清空它们的进度与用户意图无关。
      await service.commit(
        previewToken: second.previewToken,
        selectedKeys: second.recommendedKeys.toSet(),
        mode: ImportMode.fillMissing,
        now: now,
        resetLearningProgress: true,
      );

      expect(
        await (db.select(
          db.reviewLogs,
        )..where((row) => row.wordId.equals(wordId))).get(),
        isEmpty,
        reason: '复习日志应当被清空',
      );
      expect(
        await (db.select(
          db.wordReviewStats,
        )..where((row) => row.wordId.equals(wordId))).get(),
        isEmpty,
        reason: '物化统计也必须一起清掉，否则队列仍按旧历史加权',
      );
      final word = (await allWords()).firstWhere((row) => row.id == wordId);
      expect(word.masteryLevel, MasteryLevel.newWord);
      expect(word.masteryScore, 0);
    });

    test('未勾选重置时不动已有词条的复习历史', () async {
      final service = serviceWith(_noneSelector());
      // 同前一条：第二次预览必须在第一次提交之前取。
      final first = await service.preview(articleText: sampleArticle, now: now);
      final second = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      await service.commit(
        previewToken: first.previewToken,
        selectedKeys: first.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );
      final wordId = (await allWords()).first.id;
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              clientAnswerId: 'answer-kept',
              wordId: wordId,
              reviewedAt: now,
              rating: ReviewRating.good,
              questionType: QuestionType.enToZh,
              isCorrect: true,
              createdAt: now,
            ),
          );

      await service.commit(
        previewToken: second.previewToken,
        selectedKeys: second.recommendedKeys.toSet(),
        mode: ImportMode.fillMissing,
        now: now,
      );

      expect(
        await (db.select(
          db.reviewLogs,
        )..where((row) => row.wordId.equals(wordId))).get(),
        hasLength(1),
      );
    });

    test('仅新增模式下即使勾选也不重置已有词条的进度', () async {
      // 与 CSV 路径共享同一条约定（见 `csv_import_service.dart` 的
      // `_resetAtFor` 注释）：`SKIP_EXISTING` 的语义是「已有的词条完全不动」，
      // 而重置会删掉与本次导入毫无关系的复习历史。
      final service = serviceWith(_noneSelector());
      final first = await service.preview(articleText: sampleArticle, now: now);
      final second = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      await service.commit(
        previewToken: first.previewToken,
        selectedKeys: first.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );
      final wordId = (await allWords()).first.id;
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              clientAnswerId: 'answer-skip-existing',
              wordId: wordId,
              reviewedAt: now,
              rating: ReviewRating.good,
              questionType: QuestionType.enToZh,
              isCorrect: true,
              createdAt: now,
            ),
          );

      await service.commit(
        previewToken: second.previewToken,
        selectedKeys: second.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
        resetLearningProgress: true,
      );

      expect(
        await (db.select(
          db.reviewLogs,
        )..where((row) => row.wordId.equals(wordId))).get(),
        hasLength(1),
      );
    });

    test('重复提交同一篇文章不建重复词条', () async {
      final service = serviceWith(_noneSelector());
      // 两次预览都发生在第一次提交之前：第二次预览里的候选此刻还是待学，
      // 用户真的会把它们提交一次——这才是「重复提交」的真实路径。
      final first = await service.preview(articleText: sampleArticle, now: now);
      final second = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      final firstResult = await service.commit(
        previewToken: first.previewToken,
        selectedKeys: first.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );
      final secondResult = await service.commit(
        previewToken: second.previewToken,
        selectedKeys: second.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );

      expect(firstResult.createdWords, greaterThan(0));
      expect(secondResult.createdWords, 0);
      expect(secondResult.existingWords, firstResult.createdWords);
      expect((await allWords()).length, firstResult.createdWords);
      // 已有词条不再入队，初始化任务数保持第一次提交的结果。
      expect((await allJobs()).length, firstResult.createdWords);
    });

    test('全部词条都已存在时没有可提交的推荐项', () async {
      final service = serviceWith(_noneSelector());
      final first = await service.preview(articleText: sampleArticle, now: now);
      await service.commit(
        previewToken: first.previewToken,
        selectedKeys: first.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );

      final again = await service.preview(articleText: sampleArticle, now: now);

      expect(again.knownCount, again.candidates.length);
      expect(again.recommendedKeys, isEmpty);
      expect(again.recommendedTerms, isEmpty);
    });

    test('同一个预览令牌只能提交一次', () async {
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: preview.recommendedKeys.toSet(),
        mode: ImportMode.skipExisting,
        now: now,
      );

      await expectLater(
        service.commit(
          previewToken: preview.previewToken,
          selectedKeys: preview.recommendedKeys.toSet(),
          mode: ImportMode.skipExisting,
          now: now,
        ),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.importPreviewExpired,
          ),
        ),
      );
    });

    test('一个词条都没选时报参数错误', () async {
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      await expectLater(
        service.commit(
          previewToken: preview.previewToken,
          selectedKeys: const <String>{},
          mode: ImportMode.skipExisting,
          now: now,
        ),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.validationError,
          ),
        ),
      );
    });

    test('短语把 AI 意译写成初始释义，词条类型为短语', () async {
      final service = serviceWith(
        _FakeSelector(
          (_) async => const ArticleAiSelection.success(
            phrases: <ArticleAiPhrase>[
              ArticleAiPhrase(
                term: 'cognitive science',
                reason: '固定搭配',
                difficulty: 3,
                literalTranslation: '认知科学',
                freeTranslation: '认知科学（学科）',
              ),
            ],
          ),
        ),
      );
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      final key = articleCandidateKey(
        LexicalContentType.phrase,
        'cognitive science',
      );

      final result = await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: <String>{key},
        mode: ImportMode.skipExisting,
        now: now,
      );

      expect(result.createdWords, 1);
      final row = (await allWords()).single;
      expect(row.contentType, LexicalContentType.phrase);
      expect(row.entryType, EntryType.phrase);
      final content = await db.select(db.wordContents).getSingle();
      expect(content.definitionsJson, contains('认知科学（学科）'));
      expect(row.initializationStatus, InitializationStatus.ready);
    });

    test('已有词条按导入模式入队，且不计入 queuedInitializations', () async {
      await insertWord(term: 'knowledge');
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      final result = await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: <String>{
          articleCandidateKey(LexicalContentType.word, 'knowledge'),
        },
        mode: ImportMode.fillMissing,
        now: now,
      );

      expect(result.createdWords, 0);
      expect(result.existingWords, 1);
      expect(result.queuedInitializations, 0);
      final jobs = await allJobs();
      expect(jobs.single.mode, InitializationMode.fillMissingFields);
      expect(jobs.single.priority, jobPriorityFillMissing);
    });

    test('仅新增模式下已有词条不入队', () async {
      await insertWord(term: 'knowledge');
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: <String>{
          articleCandidateKey(LexicalContentType.word, 'knowledge'),
        },
        mode: ImportMode.skipExisting,
        now: now,
      );

      expect(await allJobs(), isEmpty);
    });

    test('LLM 返回词形还原（implemented → implement）时按原形建候选并重判词库', () async {
      await insertWord(term: 'reshape');
      final service = serviceWith(
        _FakeSelector(
          (_) async => const ArticleAiSelection.success(
            words: <ArticleAiWord>[
              ArticleAiWord(
                term: 'reshape',
                surfaceForm: 'reshaped',
                reason: '重塑',
                difficulty: 3,
                cefrLevel: 'B2',
                examTags: <String>['CET6'],
              ),
              ArticleAiWord(
                term: 'yield',
                surfaceForm: 'yields',
                reason: '产生、带来',
                difficulty: 4,
                cefrLevel: 'C1',
                examTags: <String>['IELTS'],
              ),
            ],
          ),
        ),
      );

      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );

      // reshape 已在词库中：还原后识别为 KNOWN 且不自动推荐。
      final reshaped = candidateOf(preview, 'reshape');
      expect(reshaped.status, ArticleCandidateStatus.known);
      expect(reshaped.surfaceForm, 'reshaped');
      // yield 不在词库中：还原为原形 yield，保留原文变形 yields 与出处句。
      final yielded = candidateOf(preview, 'yield');
      expect(yielded.status, ArticleCandidateStatus.candidate);
      expect(yielded.surfaceForm, 'yields');
      expect(yielded.examTags, <String>['IELTS']);
      expect(yielded.sourceSentence, contains('yields'));
      expect(preview.recommendedTerms, <String>['yield']);
    });

    test('提交保留原文出处例句、批次标签，且队列显式走词典源（有道优先、不含 AI）', () async {
      final service = serviceWith(_noneSelector());
      final preview = await service.preview(
        articleText: sampleArticle,
        now: now,
      );
      final targetKey = articleCandidateKey(
        LexicalContentType.word,
        'knowledge',
      );

      final result = await service.commit(
        previewToken: preview.previewToken,
        selectedKeys: <String>{targetKey},
        mode: ImportMode.skipExisting,
        tags: const <String>['经济学人', '阅读精读'],
        now: now,
      );

      expect(result.createdWordIds, hasLength(1));
      expect(result.affectedWordIds, result.createdWordIds);
      final content = await db.select(db.wordContents).getSingle();
      expect(content.examplesJson, contains('acquire knowledge'));
      expect(content.tagsJson, contains('经济学人'));
      expect(content.tagsJson, contains('阅读精读'));
      final job = (await allJobs()).single;
      expect(job.requestedProvidersJson, contains('"youdao"'));
      expect(job.requestedProvidersJson, isNot(contains('"ai"')));
    });
  });
}
