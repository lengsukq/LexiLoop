/// 词条详情 DAO 的单元测试。
///
/// 这一层承载三件容易出错、出错后又很难定位的事：
/// 1. **`word_contents` 的 JSON 列既有字符串形态又有对象形态**——旧备份里
///    两种都真实存在，解析器只认一种就会静默丢内容；
/// 2. **缺必需字段的元素要丢弃**（词根缺 `meaning`、词缀缺 `type`），
///    否则界面会出现半行空白；
/// 3. **概览计数的口径**——到期、错词、新词、连续天数各自的条件不同，
///    写错不会报错，只会显示一个看似合理的错数字。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

void main() {
  late AppDatabase db;
  late WordDetailDao dao;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = WordDetailDao(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 插入一条词条，返回其 id。
  Future<int> insertWord({
    required String term,
    LexicalContentType contentType = LexicalContentType.word,
    InitializationStatus status = InitializationStatus.ready,
    MasteryLevel masteryLevel = MasteryLevel.newWord,
    bool isSuspended = false,
  }) => db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: term,
          normalizedTerm: term.toLowerCase(),
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          entryType: EntryType.word,
          contentType: Value<LexicalContentType>(contentType),
          initializationStatus: Value<InitializationStatus>(status),
          masteryLevel: Value<MasteryLevel>(masteryLevel),
          isSuspended: Value<bool>(isSuspended),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// 写入词条内容行；未传的列用默认空值。
  Future<void> insertContents(
    int wordId, {
    String definitionsJson = '[]',
    String pronunciationsJson = '[]',
    String examplesJson = '[]',
    String synonymsJson = '[]',
    String rootsJson = '[]',
    String affixesJson = '[]',
    String summaryJson = '{}',
    String learningJson = '{}',
    String sentenceAnalysisJson = '{}',
    String tagsJson = '[]',
  }) => db
      .into(db.wordContents)
      .insert(
        WordContentsCompanion.insert(
          wordId: Value<int>(wordId),
          definitionsJson: Value<String>(definitionsJson),
          pronunciationsJson: Value<String>(pronunciationsJson),
          examplesJson: Value<String>(examplesJson),
          synonymsJson: Value<String>(synonymsJson),
          rootsJson: Value<String>(rootsJson),
          affixesJson: Value<String>(affixesJson),
          summaryJson: Value<String>(summaryJson),
          learningJson: Value<String>(learningJson),
          sentenceAnalysisJson: Value<String>(sentenceAnalysisJson),
          tagsJson: Value<String>(tagsJson),
          updatedAt: now,
        ),
      );

  /// 挂一张 FSRS 卡片。
  Future<void> insertCard(int wordId, {required int dueAt}) => db
      .into(db.reviewCards)
      .insert(
        ReviewCardsCompanion.insert(
          wordId: Value<int>(wordId),
          dueAt: dueAt,
          stability: 12.5,
          difficulty: 4.75,
          elapsedDays: 3,
          scheduledDays: 7,
          reps: 4,
          lapses: 1,
          fsrsState: 2,
          lastReviewAt: Value<int?>(now - dayMs),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// 写一行累计统计。
  Future<void> insertStats(int wordId, {required int correct}) => db
      .into(db.wordReviewStats)
      .insert(
        WordReviewStatsCompanion.insert(
          wordId: Value<int>(wordId),
          totalReviews: const Value<int>(10),
          correctReviews: Value<int>(correct),
          updatedAt: Value<int>(now),
        ),
      );

  /// 插入一条复习日志。
  Future<void> insertLog(
    int wordId, {
    required int reviewedAt,
    ReviewRating rating = ReviewRating.good,
    bool isCorrect = true,
    QuestionType questionType = QuestionType.enToZh,
    int? durationMs = 2500,
  }) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          clientAnswerId: 'answer-$wordId-$reviewedAt',
          wordId: wordId,
          reviewedAt: reviewedAt,
          rating: rating,
          questionType: questionType,
          isCorrect: isCorrect,
          durationMs: Value<int?>(durationMs),
          createdAt: reviewedAt,
        ),
      );

  /// 写一行错词状态。
  Future<void> insertWrongState(
    int wordId, {
    required bool active,
    int wrongCount = 0,
    int hardCount = 0,
    int consecutiveCorrect = 0,
    int? lastWrongAt,
    int? lastCorrectAt,
  }) => db
      .into(db.wrongWordStates)
      .insert(
        WrongWordStatesCompanion.insert(
          wordId: Value<int>(wordId),
          active: Value<bool>(active),
          wrongCount: Value<int>(wrongCount),
          hardCount: Value<int>(hardCount),
          consecutiveCorrect: Value<int>(consecutiveCorrect),
          lastWrongAt: Value<int?>(lastWrongAt),
          lastCorrectAt: Value<int?>(lastCorrectAt),
          updatedAt: now,
        ),
      );

  /// 写一条数据源调用记录。
  Future<void> insertAttempt(
    int wordId, {
    required String providerId,
    required ProviderAttemptStatus status,
    int? createdAt,
    int? durationMs,
    String? fieldsReturnedJson,
    String? metadataJson,
    String? errorCode,
    String? errorMessage,
  }) => db
      .into(db.providerAttempts)
      .insert(
        ProviderAttemptsCompanion.insert(
          wordId: wordId,
          providerId: providerId,
          status: status,
          durationMs: Value<int?>(durationMs),
          fieldsReturnedJson: Value<String?>(fieldsReturnedJson),
          metadataJson: Value<String?>(metadataJson),
          errorCode: Value<String?>(errorCode),
          errorMessage: Value<String?>(errorMessage),
          createdAt: createdAt ?? now,
        ),
      );

  group('find', () {
    test('词条不存在时返回 null', () async {
      expect(await dao.find(9999), isNull);
    });

    test('词条存在但没有内容行时仍返回详情，内容为空', () async {
      final id = await insertWord(term: 'apple', isSuspended: true);

      final detail = await dao.find(id);

      expect(detail, isNotNull);
      expect(detail!.term, 'apple');
      expect(detail.normalizedTerm, 'apple');
      expect(detail.isSuspended, isTrue);
      expect(detail.definitions, isEmpty);
      expect(detail.examples, isEmpty);
      expect(detail.hasNoContent, isTrue);
    });

    test('读回释义、发音、例句与摘要', () async {
      final id = await insertWord(term: 'apple');
      await insertContents(
        id,
        definitionsJson:
            '[{"language":"zh","text":"苹果","partOfSpeech":"n."},'
            '{"language":"en","text":"apple"}]',
        pronunciationsJson: '[{"accent":"UK","phonetic":"ˈæpl"}]',
        examplesJson: '[{"sentence":"An apple a day.","translation":"一天一苹果。"}]',
        summaryJson:
            '{"shortDefinition":"苹果","translation":null,'
            '"cefrLevel":"A1","frequency":5}',
        tagsJson: '["高频","考研"]',
      );

      final detail = await dao.find(id);

      expect(detail!.definitions, hasLength(2));
      expect(detail.definitions.first.text, '苹果');
      expect(detail.definitions.first.partOfSpeech, 'n.');
      expect(detail.pronunciations, hasLength(1));
      expect(detail.pronunciations.first.accent, Accent.uk);
      expect(detail.pronunciations.first.phonetic, 'ˈæpl');
      expect(detail.examples, hasLength(1));
      expect(detail.examples.first.translation, '一天一苹果。');
      expect(detail.summary.cefrLevel, 'A1');
      // 数字形态的词频也要能读成文本，而不是整条丢失。
      expect(detail.summary.frequency, '5');
      expect(detail.tags, <String>['高频', '考研']);
    });

    test('相关词条同时兼容字符串形态与对象形态', () async {
      final id = await insertWord(term: 'apple');
      await insertContents(
        id,
        synonymsJson: '''
[
  "fruit",
  {
    "word": "pome",
    "translation": "梨果",
    "partOfSpeech": "n.",
    "relation": "近义",
    "source": "ai",
    "difference": "pome 指仁果"
  }
]''',
      );

      final detail = await dao.find(id);

      expect(detail!.synonyms, hasLength(2));
      expect(detail.synonyms.first.word, 'fruit');
      expect(detail.synonyms.first.translation, isNull);
      expect(detail.synonyms.last.word, 'pome');
      expect(detail.synonyms.last.translation, '梨果');
      expect(detail.synonyms.last.difference, 'pome 指仁果');
    });

    test('词根与词缀缺必需字段的条目被丢弃', () async {
      final id = await insertWord(term: 'malformed');
      await insertContents(
        id,
        rootsJson:
            '[{"root":"mal","meaning":"坏","origin":"拉丁语"},'
            '{"meaning":"缺词根"},{"root":"缺含义"}]',
        affixesJson:
            '[{"value":"un-","meaning":"否定","type":"PREFIX"},'
            '{"value":"-tion","meaning":"名词后缀","type":"SUFFIX"},'
            '{"value":"-x","meaning":"缺类型"},'
            '{"value":"-y","type":"缺含义"},'
            '{"value":"","meaning":"缺值","type":"SUFFIX"}]',
      );

      final detail = await dao.find(id);

      expect(detail!.roots, hasLength(1));
      expect(detail.roots.single.root, 'mal');
      expect(detail.roots.single.origin, '拉丁语');
      expect(detail.affixes, hasLength(2));
      expect(detail.affixes.first.kind, AffixKind.prefix);
      expect(detail.affixes.last.kind, AffixKind.suffix);
    });

    test('学习揭示只读取当前词条的助记与词根词缀并兼容简化 CSV 形状', () async {
      final id = await insertWord(term: 'misunderstanding');
      await insertContents(
        id,
        rootsJson:
            '[{"root":"under","meaning":"在下面"},'
            '{"root":"stand","source":"easydict-csv"}]',
        affixesJson:
            '[{"value":"mis-","meaning":"错误","type":"PREFIX"},'
            '{"affix":"un-","source":"easydict-csv"}]',
        learningJson: '{"mnemonic":"先站在下面再理解"}',
      );
      final otherId = await insertWord(term: 'unrelated');
      await insertContents(
        otherId,
        rootsJson: '[{"root":"other","meaning":"别的"}]',
      );

      final reveal = await dao.studyRevealContent(id);

      expect(reveal.mnemonic, '先站在下面再理解');
      expect(reveal.roots.map((item) => item.root), <String>['under', 'stand']);
      expect(reveal.roots.last.meaning, isNull);
      expect(reveal.affixes.map((item) => item.value), <String>['mis-', 'un-']);
      expect(reveal.affixes.map((item) => item.kind), <AffixKind>[
        AffixKind.prefix,
        AffixKind.prefix,
      ]);
      expect(reveal.affixes.last.meaning, isNull);
    });

    test('缺失或无效的学习揭示内容退化为空', () async {
      final id = await insertWord(term: 'empty');
      expect((await dao.studyRevealContent(id)).isEmpty, isTrue);
      expect((await dao.studyRevealContent(9999)).isEmpty, isTrue);

      await insertContents(id, rootsJson: 'not-json', learningJson: 'not-json');
      expect((await dao.studyRevealContent(id)).isEmpty, isTrue);
    });

    test('非法 JSON 不抛异常，退化为空内容', () async {
      final id = await insertWord(term: 'broken');
      await insertContents(
        id,
        definitionsJson: 'not json',
        examplesJson: '{"sentence":"对象而非数组"}',
        summaryJson: '[]',
      );

      final detail = await dao.find(id);

      expect(detail!.definitions, isEmpty);
      expect(detail.examples, isEmpty);
      expect(detail.summary.isEmpty, isTrue);
      expect(detail.hasNoContent, isTrue);
    });

    test('解析助记与句子分析（对象与字符串两种条目形态）', () async {
      final id = await insertWord(term: 'take off');
      await insertContents(
        id,
        learningJson:
            '{"pronunciationTip":"连读","mnemonic":"起飞即离开",'
            '"commonMistakes":["误用为 take of"]}',
        sentenceAnalysisJson: '''
{
  "grammarPattern": "S+V+O",
  "grammarExplanation": "主谓宾",
  "grammarNotes": ["要点一"],
  "keyExpressions": [
    "take off",
    {"expression": "look after", "translation": "照顾"}
  ],
  "variations": [{"type": "被动", "sentence": "It was taken off."}]
}''',
      );

      final detail = await dao.find(id);

      expect(detail!.learning.mnemonic, '起飞即离开');
      expect(detail.learning.commonMistakes, hasLength(1));
      final analysis = detail.sentenceAnalysis;
      expect(analysis.grammarPattern, 'S+V+O');
      expect(analysis.grammarNotes, <String>['要点一']);
      expect(analysis.keyExpressions, hasLength(2));
      expect(analysis.keyExpressions.first.text, 'take off');
      expect(analysis.keyExpressions.last.text, 'look after');
      expect(analysis.variations.single.label, '被动');
      expect(analysis.variations.single.text, 'It was taken off.');
    });

    test('读回数据源时间与最后更新时间', () async {
      final id = await insertWord(term: 'apple');

      await (db.update(db.words)..where((row) => row.id.equals(id))).write(
        const WordsCompanion(
          sourceCreatedAt: Value<int>(1546300800000),
          updatedAt: Value<int>(1772000000000),
        ),
      );

      final detail = await dao.find(id);

      expect(detail!.createdAt, now);
      expect(detail.sourceCreatedAt, 1546300800000);
      expect(detail.updatedAt, 1772000000000);
    });

    test('没有 source_created_at 时保持 null 而不是回落到 created_at', () async {
      final id = await insertWord(term: 'apple');

      final detail = await dao.find(id);

      expect(detail!.sourceCreatedAt, isNull);
      expect(detail.updatedAt, now);
    });
  });

  group('learningSnapshot', () {
    test('无卡片无统计时返回全默认值', () async {
      final id = await insertWord(term: 'apple');

      final snapshot = await dao.learningSnapshot(id);

      expect(snapshot.hasCard, isFalse);
      expect(snapshot.totalReviews, 0);
      expect(snapshot.accuracy, isNull);
    });

    test('有卡片与统计时读回 FSRS 状态与累计正确率', () async {
      final id = await insertWord(term: 'apple');
      await insertCard(id, dueAt: now + dayMs);
      await insertStats(id, correct: 8);

      final snapshot = await dao.learningSnapshot(id);

      expect(snapshot.hasCard, isTrue);
      expect(snapshot.dueAt, now + dayMs);
      expect(snapshot.stability, 12.5);
      expect(snapshot.difficulty, 4.75);
      expect(snapshot.scheduledDays, 7);
      expect(snapshot.reps, 4);
      expect(snapshot.lapses, 1);
      expect(snapshot.fsrsState, fsrsStateReview);
      expect(snapshot.totalReviews, 10);
      expect(snapshot.accuracy, closeTo(0.8, 0.0001));
    });

    test('没有 wrong_word_states 行时错词状态全为空', () async {
      final id = await insertWord(term: 'apple');
      await insertCard(id, dueAt: now);

      final snapshot = await dao.learningSnapshot(id);

      expect(snapshot.isUntouched, isTrue);
      expect(snapshot.isWrongWord, isFalse);
      expect(snapshot.wrongCount, 0);
      expect(snapshot.lastWrongAt, isNull);
    });

    test('读回错误次数、困难次数与连续答对', () async {
      final id = await insertWord(term: 'raise');
      await insertWrongState(
        id,
        active: true,
        wrongCount: 3,
        hardCount: 2,
        lastWrongAt: now - hourMs,
      );

      final snapshot = await dao.learningSnapshot(id);

      expect(snapshot.isUntouched, isFalse);
      expect(snapshot.isWrongWord, isTrue);
      expect(snapshot.wrongCount, 3);
      expect(snapshot.hardCount, 2);
      expect(snapshot.consecutiveCorrect, 0);
      expect(snapshot.lastWrongAt, now - hourMs);
    });

    test('已解除的错词仍保留历史错误次数', () async {
      final id = await insertWord(term: 'raise');
      await insertWrongState(
        id,
        active: false,
        wrongCount: 4,
        consecutiveCorrect: 3,
        lastCorrectAt: now,
      );

      final snapshot = await dao.learningSnapshot(id);

      expect(snapshot.isWrongWord, isFalse);
      expect(snapshot.wrongCount, 4);
      expect(snapshot.consecutiveCorrect, 3);
    });
  });

  group('providerAttempts', () {
    test('没有调用记录时返回空列表', () async {
      final id = await insertWord(term: 'apple');

      expect(await dao.providerAttempts(id), isEmpty);
    });

    test('读出卡片要渲染的每一个字段', () async {
      final id = await insertWord(term: 'raise');
      await insertAttempt(
        id,
        providerId: 'ai:opencode-zen:deepseek-v4-flash-free',
        status: ProviderAttemptStatus.success,
        durationMs: 2142,
        fieldsReturnedJson: '["definitions","examples"]',
        metadataJson: '{"model":"deepseek-v4","qualityScore":79}',
      );

      final attempt = (await dao.providerAttempts(id)).single;

      expect(attempt.providerId, 'ai:opencode-zen:deepseek-v4-flash-free');
      expect(attempt.status, ProviderAttemptStatus.success);
      expect(attempt.qualityScore, 79);
      expect(attempt.durationMs, 2142);
      expect(attempt.fieldsReturned, <String>['definitions', 'examples']);
      expect(attempt.errorMessage, isNull);
      expect(attempt.createdAt, now);
    });

    test('失败记录带上错误码与错误说明', () async {
      final id = await insertWord(term: 'raise');
      await insertAttempt(
        id,
        providerId: 'youdao',
        status: ProviderAttemptStatus.failed,
        errorCode: 'PROVIDER_TRANSIENT_FAILURE',
        errorMessage: '连接超时',
      );

      final attempt = (await dao.providerAttempts(id)).single;

      expect(attempt.status, ProviderAttemptStatus.failed);
      expect(attempt.errorCode, 'PROVIDER_TRANSIENT_FAILURE');
      expect(attempt.errorMessage, '连接超时');
      expect(attempt.qualityScore, isNull);
    });

    test('按时间倒序并受 limit 限制', () async {
      final id = await insertWord(term: 'raise');
      await insertAttempt(
        id,
        providerId: 'ecdict',
        status: ProviderAttemptStatus.success,
        createdAt: now - 2 * dayMs,
      );
      await insertAttempt(
        id,
        providerId: 'youdao',
        status: ProviderAttemptStatus.success,
        createdAt: now,
      );
      await insertAttempt(
        id,
        providerId: 'merriam-webster',
        status: ProviderAttemptStatus.empty,
        createdAt: now - dayMs,
      );

      final limited = await dao.providerAttempts(id, limit: 2);

      expect(limited.map((one) => one.providerId), <String>[
        'youdao',
        'merriam-webster',
      ]);
    });

    test('只返回该词条的记录', () async {
      final first = await insertWord(term: 'apple');
      final second = await insertWord(term: 'banana');
      await insertAttempt(
        first,
        providerId: 'ecdict',
        status: ProviderAttemptStatus.success,
      );
      await insertAttempt(
        second,
        providerId: 'youdao',
        status: ProviderAttemptStatus.success,
      );

      final attempts = await dao.providerAttempts(second);

      expect(attempts, hasLength(1));
      expect(attempts.single.providerId, 'youdao');
    });

    test('未知状态退化为「无内容」而不是丢弃该行', () async {
      final id = await insertWord(term: 'raise');
      await db
          .into(db.providerAttempts)
          .insert(
            ProviderAttemptsCompanion.insert(
              wordId: id,
              providerId: 'legacy-provider',
              status: ProviderAttemptStatus.success,
              createdAt: now,
            ),
          );
      await db.customUpdate(
        "UPDATE provider_attempts SET status = 'PARTIAL' WHERE word_id = ?",
        variables: <Variable<Object>>[Variable<int>(id)],
        updateKind: UpdateKind.update,
      );

      final attempt = (await dao.providerAttempts(id)).single;

      expect(attempt.status, ProviderAttemptStatus.empty);
    });
  });

  group('元数据补平', () {
    /// 真实备份（`lexiloop-backup-20261014-222752.json`，word_id = 163，raise）
    /// 的原始 JSON，原样贴进来：这些字段如果被解析层丢掉，界面就再也拿不回来，
    /// 而合成 fixture 很容易「顺手」把字段名写对，掩盖真实的键名差异。
    test('释义的 usageNote / senseId / register 逐字读回', () async {
      final id = await insertWord(term: 'raise');
      await insertContents(id, definitionsJson: _realDefinitionsJson);

      final definitions = (await dao.find(id))!.definitions;

      expect(definitions, hasLength(2));
      expect(definitions.first.usageNote, contains('raising children'));
      expect(definitions.first.senseId, 'raise_v_bring_up');
      expect(definitions.first.register, 'NEUTRAL');
      expect(definitions.last.usageNote, contains('formal discussions'));
    });

    test('例句的 difficulty / senseId 逐字读回', () async {
      final id = await insertWord(term: 'raise');
      await insertContents(id, examplesJson: _realExamplesJson);

      final examples = (await dao.find(id))!.examples;

      expect(examples, hasLength(2));
      expect(examples.first.difficulty, 'EASY');
      expect(examples.first.senseId, 'raise_v_lift');
      expect(examples.first.translation, '她举手提问。');
      expect(examples.last.difficulty, 'NORMAL');
    });

    test('关键表达的 meaning / note 与相似例句的 translation / focus 不丢', () async {
      final id = await insertWord(term: 'raise');
      await insertContents(id, sentenceAnalysisJson: _realSentenceAnalysisJson);

      final analysis = (await dao.find(id))!.sentenceAnalysis;

      final key = analysis.keyExpressions;
      expect(key, hasLength(2));
      expect(key.first.text, 'raise the flag');
      expect(key.first.meaning, '升旗');
      expect(key.first.note, 'Can be literal or symbolic.');

      final similar = analysis.similarExamples;
      expect(similar, hasLength(2));
      expect(similar.first.text, 'She raised her voice to be heard.');
      expect(similar.first.translation, '她提高嗓门以便被听到。');
      expect(similar.first.focus, 'raise + voice');

      expect(
        analysis.variations.single.text,
        'The flag was raised by the soldiers.',
      );
    });

    test('详情页与删除接口对例句的可见集合判定一致', () async {
      // 原始数组里混了「非对象」与「空句子」，界面只渲染后面三条；
      // 删除接口必须按同一套规则换算下标，否则会删错条目。
      const raw =
          '[{"sentence":"a"},null,{"sentence":""},'
          '{"sentence":"b"},{"sentence":"c"}]';

      expect(parseDetailExamples(raw).map((one) => one.sentence), <String>[
        'a',
        'b',
        'c',
      ]);
      expect(detailExamplePositions(raw), <int>[0, 3, 4]);
    });
  });

  group('recentLogs', () {
    test('按时间倒序并受 limit 限制', () async {
      final id = await insertWord(term: 'apple');
      await insertLog(id, reviewedAt: now - 2 * dayMs);
      await insertLog(id, reviewedAt: now - dayMs);
      await insertLog(id, reviewedAt: now);

      final all = await dao.recentLogs(id);
      final limited = await dao.recentLogs(id, limit: 2);

      expect(all.map((entry) => entry.reviewedAt), <int>[
        now,
        now - dayMs,
        now - 2 * dayMs,
      ]);
      expect(limited, hasLength(2));
      expect(limited.first.reviewedAt, now);
      expect(limited.last.reviewedAt, now - dayMs);
    });

    test('只返回该词条的日志', () async {
      final first = await insertWord(term: 'apple');
      final second = await insertWord(term: 'banana');
      await insertLog(first, reviewedAt: now);
      await insertLog(second, reviewedAt: now);

      final logs = await dao.recentLogs(second);

      expect(logs, hasLength(1));
      expect(logs.single.id, isNotNull);
    });

    test('读回评级、正误、题型与耗时', () async {
      final id = await insertWord(term: 'apple');
      await insertLog(
        id,
        reviewedAt: now,
        rating: ReviewRating.again,
        isCorrect: false,
        questionType: QuestionType.clozeSentence,
        durationMs: 4200,
      );

      final entry = (await dao.recentLogs(id)).single;

      expect(entry.rating, ReviewRating.again);
      expect(entry.isCorrect, isFalse);
      expect(entry.questionType, QuestionType.clozeSentence);
      expect(entry.durationMs, 4200);
    });
  });

  group('overview', () {
    test('空库时所有计数为 0', () async {
      final overview = await dao.overview(now);

      expect(overview.totalWords, 0);
      expect(overview.byMastery, isEmpty);
      expect(overview.dueToday, 0);
      expect(overview.wrongWords, 0);
      expect(overview.reviewedToday, 0);
      expect(overview.streakDays, 0);
      expect(overview.newWordsAvailable, 0);
    });

    test('到期、错词、新词与今日已答的口径各自正确', () async {
      final due = await insertWord(
        term: 'due',
        masteryLevel: MasteryLevel.learning,
      );
      final suspended = await insertWord(term: 'suspended', isSuspended: true);
      await insertWord(term: 'fresh');
      await insertWord(term: 'pending', status: InitializationStatus.pending);
      final future = await insertWord(term: 'future');

      await insertCard(due, dueAt: now - 1000);
      await insertCard(suspended, dueAt: now - 1000);
      await insertCard(future, dueAt: now + dayMs);
      await db
          .into(db.wrongWordStates)
          .insert(
            WrongWordStatesCompanion.insert(
              wordId: Value<int>(due),
              active: const Value<bool>(true),
              updatedAt: now,
            ),
          );
      await db
          .into(db.wrongWordStates)
          .insert(
            WrongWordStatesCompanion.insert(
              wordId: Value<int>(suspended),
              active: const Value<bool>(false),
              updatedAt: now,
            ),
          );

      // 今天一条、昨天一条：今日已答只算今天那条。
      final today = startOfLocalDay(now);
      await insertLog(due, reviewedAt: today + hourMs);
      await insertLog(due, reviewedAt: today - hourMs);

      final overview = await dao.overview(now);

      expect(overview.totalWords, 5);
      expect(overview.dueToday, 1, reason: '已暂停与未到期的卡片不算到期');
      expect(overview.wrongWords, 1, reason: '只算 active 的错词状态');
      expect(overview.reviewedToday, 1);
      expect(overview.newWordsAvailable, 1, reason: '只有 fresh 既无卡片、未暂停、且已就绪');
      expect(overview.byMastery[MasteryLevel.learning], 1);
      expect(overview.byMastery[MasteryLevel.newWord], 4);
    });

    test('连续天数跨自然日计算', () async {
      final id = await insertWord(term: 'apple');
      final today = startOfLocalDay(now);
      await insertLog(id, reviewedAt: today + hourMs);
      await insertLog(id, reviewedAt: today - hourMs);

      expect((await dao.overview(now)).streakDays, 2);
    });

    test('中间断档时只数到断档处', () async {
      final id = await insertWord(term: 'apple');
      final today = startOfLocalDay(now);
      await insertLog(id, reviewedAt: today + hourMs);
      await insertLog(id, reviewedAt: today - hourMs);
      await insertLog(id, reviewedAt: today - 3 * dayMs);

      expect((await dao.overview(now)).streakDays, 2);
    });

    test('今天还没复习时从昨天起算', () async {
      final id = await insertWord(term: 'apple');
      await insertLog(id, reviewedAt: startOfLocalDay(now) - hourMs);

      expect((await dao.overview(now)).streakDays, 1);
    });

    test('昨天的日志不重复计入今日已答', () async {
      final id = await insertWord(term: 'apple');
      await insertLog(id, reviewedAt: startOfLocalDay(now) - hourMs);

      final overview = await dao.overview(now);

      expect(overview.reviewedToday, 0);
      expect(overview.streakDays, 1);
    });
  });

  test('dateKey 与 localDayOrdinal 的口径一致', () {
    // 概览的连续天数依赖这两个函数；这里固化它们的关系，
    // 避免将来有人用 dayMs 相减改写跨日判断。
    expect(dateKey(now), '2026-03-01');
    expect(
      localDayOrdinal(now) - localDayOrdinal(now - dayMs),
      1,
      reason: '昨天与今天的日序数相差 1',
    );
  });
}

// ═══════════════════════════════════════════════════════════════
// 真实备份 fixture
//
// 三段 JSON 逐字摘自 `lexiloop-backup-20261014-222752.json`
// 中 word_id = 163（raise）的 `word_contents` 行。
//
// **为什么要贴原文而不是手写一个「同形」的 fixture**：这些字段名
// （`usageNote` / `senseId` / `register` / `focus`）来自旧版服务端，
// 手写 fixture 时人很容易按直觉写成 `usage_note` / `sense_id`，
// 测试照样绿，但真实备份照样解析不出来——那正是这个 fixture 要防的事。
// ═══════════════════════════════════════════════════════════════

/// 真实备份里的 `definitions_json`（前两条）。
const String _realDefinitionsJson =
    '[{"partOfSpeech":"verb", '
    '"source":"ai:opencode-zen:deepseek-v4-flash-free", '
    '"isUserEdited":false,"senseId":"raise_v_bring_up", '
    '"register":"NEUTRAL", '
    '"usageNote":"Used for raising children or animals; '
    'often implies long-term care.", '
    '"language":"en", '
    '"text":"To take care of and educate a child until they are grown up; '
    'to breed or keep animals."}, '
    '{"partOfSpeech":"verb", '
    '"source":"ai:opencode-zen:deepseek-v4-flash-free", '
    '"isUserEdited":false,"senseId":"raise_v_mention", '
    '"register":"NEUTRAL", '
    '"usageNote":"Common in formal discussions, meetings, and debates.", '
    '"language":"en", '
    '"text":"To mention or bring up a subject, question, '
    'or issue for discussion."}]';

/// 真实备份里的 `examples_json`（前两条）。
const String _realExamplesJson =
    '[{"sentence":"She raised her hand to ask a question.", '
    '"translation":"她举手提问。", '
    '"source":"ai:opencode-zen:deepseek-v4-flash-free", '
    '"isUserAdded":false,"senseId":"raise_v_lift","difficulty":"EASY"}, '
    '{"sentence":"He raised the heavy box onto the shelf.", '
    '"translation":"他把沉重的箱子举到架子上。", '
    '"source":"ai:opencode-zen:deepseek-v4-flash-free", '
    '"isUserAdded":false,"senseId":"raise_v_lift",'
    '"difficulty":"NORMAL"}]';

/// 真实备份里的 `sentence_analysis_json`（截取三个分组）。
const String _realSentenceAnalysisJson = '''
{
  "grammarPattern": "Subject + raise + Object",
  "keyExpressions": [
    {"expression": "raise the flag", "meaning": "升旗",
     "note": "Can be literal or symbolic."},
    {"expression": "raise a toast", "meaning": "举杯祝酒",
     "note": "Used when proposing a drink in honour of someone."}
  ],
  "similarExamples": [
    {"sentence": "She raised her voice to be heard.",
     "translation": "她提高嗓门以便被听到。", "focus": "raise + voice"},
    {"sentence": "They raised money for charity.",
     "translation": "他们为慈善筹款。", "focus": "raise + money"}
  ],
  "variations": [
    {"sentence": "The flag was raised by the soldiers.",
     "translation": "士兵们升起了旗帜。"}
  ]
}''';
