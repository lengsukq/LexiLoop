/// 统计查询的单元测试。
///
/// 重点验证三件容易算错的事：**日界**（跨自然日）、**连续天数**
/// （今天没学不该算断签）、**时长上界**（挂机不该污染统计）。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

void main() {
  late AppDatabase db;
  late StatisticsDao dao;

  /// 以「今天 10:00」为基准，避免测试在午夜附近跑时跨日。
  late int today;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = StatisticsDao(db);
    final now = DateTime.now();
    today = DateTime(now.year, now.month, now.day, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord({
    String term = 'apple',
    MasteryLevel mastery = MasteryLevel.newWord,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            masteryLevel: Value<MasteryLevel>(mastery),
            createdAt: today,
            updatedAt: today,
          ),
        );
    return id;
  }

  var answerSeq = 0;

  Future<void> insertLog({
    required int wordId,
    required int reviewedAt,
    bool isCorrect = true,
    int? durationMs = 3000,
    ReviewRating rating = ReviewRating.good,
    QuestionType questionType = QuestionType.zhToEnSpelling,
  }) async {
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            clientAnswerId: 'c${answerSeq++}',
            wordId: wordId,
            reviewedAt: reviewedAt,
            rating: rating,
            questionType: questionType,
            isCorrect: isCorrect,
            durationMs: Value<int?>(durationMs),
            createdAt: reviewedAt,
          ),
        );
  }

  /// 插一条学习会话。
  ///
  /// [completedCount] 默认 5，即「一个正常做完的会话」；传 0 表示一条题都没做的
  /// 空会话，[skippedCount] 默认 0 表示没跳过任何题。
  Future<void> insertSession({
    required int startedAt,
    int completedCount = 5,
    int skippedCount = 0,
    StudyMode sessionType = StudyMode.daily,
  }) async {
    await db
        .into(db.studySessions)
        .insert(
          StudySessionsCompanion.insert(
            sessionType: sessionType,
            startedAt: startedAt,
            completedCount: Value<int>(completedCount),
            skippedCount: Value<int>(skippedCount),
            createdAt: startedAt,
          ),
        );
  }

  group('dailyTrend', () {
    test('没有记录时返回补齐的零值序列', () async {
      final trend = await dao.dailyTrend(now: today, days: 7);
      expect(trend, hasLength(7));
      expect(trend.every((item) => item.reviewed == 0), isTrue);
      expect(trend.last.dateKey, dateKey(today));
    });

    test('按自然日聚合，并补齐缺失的日子', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today);
      await insertLog(wordId: wordId, reviewedAt: today, isCorrect: false);
      await insertLog(wordId: wordId, reviewedAt: today - 2 * dayMs);

      final trend = await dao.dailyTrend(now: today, days: 5);
      expect(trend, hasLength(5));
      // 序列按日期升序，最后一项是今天。
      expect(trend.last.reviewed, 2);
      expect(trend.last.correct, 1);
      expect(trend.last.accuracy, 0.5);
      // 倒数第三天（两天前）有一条。
      expect(trend[trend.length - 3].reviewed, 1);
      // 其余为 0。
      expect(trend[0].reviewed, 0);
      expect(trend[1].reviewed, 0);
    });

    test('窗口外的记录不计入', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today - 30 * dayMs);

      final trend = await dao.dailyTrend(now: today, days: 7);
      expect(trend.every((item) => item.reviewed == 0), isTrue);
    });

    test('统计「首次接触」的新词数', () async {
      final first = await insertWord();
      final second = await insertWord(term: 'banana');
      // apple 首次在两天前，今天又复习一次；banana 首次在今天。
      await insertLog(wordId: first, reviewedAt: today - 2 * dayMs);
      await insertLog(wordId: first, reviewedAt: today);
      await insertLog(wordId: second, reviewedAt: today);

      final trend = await dao.dailyTrend(now: today, days: 5);
      expect(trend.last.newWords, 1, reason: '今天首次接触的只有 banana');
      expect(trend[trend.length - 3].newWords, 1, reason: '两天前首次接触 apple');
    });

    test('挂机时长按上限计入', () async {
      final wordId = await insertWord();
      await insertLog(
        wordId: wordId,
        reviewedAt: today,
        durationMs: maxActiveAnswerDurationMs * 100,
      );

      final trend = await dao.dailyTrend(now: today, days: 3);
      expect(trend.last.durationMs, maxActiveAnswerDurationMs);
    });

    test('未测量耗时不贡献时长', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today, durationMs: null);

      final trend = await dao.dailyTrend(now: today, days: 3);
      expect(trend.last.durationMs, 0);
      expect(trend.last.reviewed, 1);
    });

    test('补齐的零值序列里会话类字段都是 0', () async {
      final trend = await dao.dailyTrend(now: today, days: 4);

      expect(
        trend.every((item) => item.again == 0 && item.skipped == 0),
        isTrue,
      );
      expect(trend.every((item) => item.sessions == 0), isTrue);
    });

    test('again 只数评级为 AGAIN 的作答', () async {
      final wordId = await insertWord();
      await insertLog(
        wordId: wordId,
        reviewedAt: today,
        isCorrect: false,
        rating: ReviewRating.again,
      );
      await insertLog(
        wordId: wordId,
        reviewedAt: today,
        isCorrect: false,
        rating: ReviewRating.hard,
      );
      await insertLog(
        wordId: wordId,
        reviewedAt: today,
        rating: ReviewRating.easy,
      );

      final trend = await dao.dailyTrend(now: today, days: 3);
      expect(trend.last.reviewed, 3);
      expect(trend.last.again, 1);
      expect(trend.last.correct, 1);
    });

    test('sessions 跳过一条题都没做的空会话', () async {
      await insertSession(startedAt: today);
      await insertSession(startedAt: today, completedCount: 0);

      final trend = await dao.dailyTrend(now: today, days: 3);
      expect(trend.last.sessions, 1);
    });

    test('skipped 取会话的 skipped_count 之和，按会话开始日的自然日归并', () async {
      await insertSession(startedAt: today, completedCount: 4, skippedCount: 2);
      await insertSession(
        startedAt: today + hourMs,
        completedCount: 1,
        skippedCount: 3,
      );
      await insertSession(
        startedAt: today - 2 * dayMs,
        completedCount: 2,
        skippedCount: 7,
      );

      final trend = await dao.dailyTrend(now: today, days: 5);
      expect(trend.last.sessions, 2, reason: '同一天的两个会话都算');
      expect(trend.last.skipped, 5, reason: '2 + 3');
      expect(trend[trend.length - 3].skipped, 7, reason: '两天前那个会话');
    });

    test('skipped 与会话无关：review_logs 不参与', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today, isCorrect: false);

      final trend = await dao.dailyTrend(now: today, days: 3);
      expect(trend.last.reviewed, 1);
      expect(trend.last.skipped, 0, reason: 'skipped 只来自 study_sessions');
      expect(trend.last.sessions, 0);
    });

    test('只有会话没有复习记录的那天也要产出', () async {
      await insertSession(
        startedAt: today - dayMs,
        completedCount: 3,
        skippedCount: 1,
      );

      final trend = await dao.dailyTrend(now: today, days: 3);
      expect(trend.last.reviewed, 0);
      expect(trend.last.sessions, 0);
      expect(trend[trend.length - 2].sessions, 1);
      expect(trend[trend.length - 2].skipped, 1);
    });

    test('窗口外的会话不计入', () async {
      await insertSession(startedAt: today - 30 * dayMs, skippedCount: 4);

      final trend = await dao.dailyTrend(now: today, days: 7);
      expect(trend.every((item) => item.sessions == 0), isTrue);
      expect(trend.every((item) => item.skipped == 0), isTrue);
    });

    test('空会话的 skipped_count 也不计入', () async {
      await insertSession(startedAt: today, completedCount: 0, skippedCount: 9);

      final trend = await dao.dailyTrend(now: today, days: 3);
      expect(trend.last.sessions, 0);
      expect(trend.last.skipped, 0);
    });
  });

  group('overview', () {
    test('空库时全部为零', () async {
      final overview = await dao.overview(today);
      expect(overview.totalWords, 0);
      expect(overview.totalReviews, 0);
      expect(overview.accuracy, 0);
      expect(overview.streakDays, 0);
      expect(overview.activeDays, 0);
      expect(overview.byMastery.values.every((count) => count == 0), isTrue);
      expect(overview.byMastery.keys, containsAll(MasteryLevel.values));
    });

    test('按掌握等级分组计数', () async {
      await insertWord(term: 'a');
      await insertWord(term: 'b', mastery: MasteryLevel.familiar);
      await insertWord(term: 'c', mastery: MasteryLevel.familiar);

      final overview = await dao.overview(today);
      expect(overview.totalWords, 3);
      expect(overview.byMastery[MasteryLevel.newWord], 1);
      expect(overview.byMastery[MasteryLevel.familiar], 2);
      expect(overview.byMastery[MasteryLevel.mastered], 0);
    });

    test('累计作答与正确率', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today);
      await insertLog(wordId: wordId, reviewedAt: today, isCorrect: false);
      await insertLog(wordId: wordId, reviewedAt: today);

      final overview = await dao.overview(today);
      expect(overview.totalReviews, 3);
      expect(overview.totalCorrect, 2);
      expect(overview.accuracy, closeTo(2 / 3, 1e-9));
    });

    test('学习天数是去重后的自然日数', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today);
      await insertLog(wordId: wordId, reviewedAt: today + hourMs);
      await insertLog(wordId: wordId, reviewedAt: today - dayMs);

      final overview = await dao.overview(today);
      expect(overview.activeDays, 2);
    });
  });

  group('streakDays', () {
    test('无记录为 0', () async {
      expect(await dao.streakDays(today), 0);
    });

    test('只有今天记录时为 1', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today);
      expect(await dao.streakDays(today), 1);
    });

    test('今天没记录但昨天有，仍从昨天起算', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today - dayMs);
      expect(await dao.streakDays(today), 1);
    });

    test('连续三天为 3', () async {
      final wordId = await insertWord();
      for (var offset = 0; offset < 3; offset += 1) {
        await insertLog(wordId: wordId, reviewedAt: today - offset * dayMs);
      }
      expect(await dao.streakDays(today), 3);
    });

    test('中间断档时只数到断点', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today);
      await insertLog(wordId: wordId, reviewedAt: today - dayMs);
      // 缺今天-2 天
      await insertLog(wordId: wordId, reviewedAt: today - 3 * dayMs);
      expect(await dao.streakDays(today), 2);
    });

    test('两天前有记录但今天和昨天都没有时为 0', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today - 2 * dayMs);
      expect(await dao.streakDays(today), 0);
    });
  });

  group('accuracyByQuestionType', () {
    test('按题型分组并按作答次数降序', () async {
      final wordId = await insertWord();
      await insertLog(wordId: wordId, reviewedAt: today);
      await insertLog(wordId: wordId, reviewedAt: today);
      await insertLog(
        wordId: wordId,
        reviewedAt: today,
        isCorrect: false,
        questionType: QuestionType.enToZhChoice,
      );

      final accuracy = await dao.accuracyByQuestionType();
      expect(accuracy, hasLength(2));
      expect(accuracy.first.questionType, QuestionType.zhToEnSpelling);
      expect(accuracy.first.attempts, 2);
      expect(accuracy.first.correct, 2);
      expect(accuracy.first.accuracy, 1);
      expect(accuracy.last.questionType, QuestionType.enToZhChoice);
      expect(accuracy.last.accuracy, 0);
    });

    test('空库时为空列表', () async {
      expect(await dao.accuracyByQuestionType(), isEmpty);
    });
  });

  group('recentResults', () {
    test('按时间倒序且受 limit 限制', () async {
      final wordId = await insertWord();
      for (var index = 0; index < 5; index += 1) {
        await insertLog(
          wordId: wordId,
          reviewedAt: today + index * minuteMs,
          isCorrect: index.isEven,
        );
      }

      final results = await dao.recentResults(limit: 3);
      expect(results, hasLength(3));
      // 由新到旧：index 4（对）、3（错）、2（对）。
      expect(results, <bool>[true, false, true]);
    });

    test('空库时为空列表', () async {
      expect(await dao.recentResults(limit: recentResultsLimit), isEmpty);
    });
  });
}
