/// **重放 ≡ 复习流水线**。
///
/// 这是合并同步里风险最高的一块：合并后的卡片、错词状态、熟练度都是「把流水
/// 重新走一遍」算出来的，只要重放与真实流水线有一个字段对不上，用户就会看到
/// 「合并之后我的到期日变了 / 错词本空了」。
///
/// 因此这里不自己复述一遍逻辑，而是**真的跑 `ReviewService.processAnswer`**
/// （连库、写日志、推进 FSRS、更新错词与熟练度），再把同一批 `review_logs`
/// 拿去重放，逐字段对比。
///
/// 一旦将来有人往流水线里加了一步（例如新增一个影响熟练度的输入），
/// 而没有同步更新重放，这条用例就会红。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/merge/learning_replay.dart';
import 'package:lexiloop/services/review_service.dart';
import 'package:lexiloop/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late ReviewService service;
  late FsrsScheduler scheduler;
  late int start;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final settings = SettingsService(SettingsDao(db));
    service = ReviewService(db, settings);
    scheduler = FsrsScheduler(
      requestRetention: (await settings.load()).studyPlan.targetRetentionRate,
    );
    start = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 插一个可学习的词条。
  Future<int> insertWord(String term) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: start,
            updatedAt: start,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: const Value<String>(
              '[{"language":"zh","text":"苹果"}]',
            ),
            updatedAt: start,
          ),
        );
    return id;
  }

  /// 按给定脚本依次作答；每个元素是（评级, 答对与否, 相隔天数）。
  ///
  /// `isCorrect` 与评级分开传，是因为流水线里「自评记得但答错」会被降级——
  /// 那条路径同样要被重放复现。
  Future<void> answerSeries(
    int wordId,
    List<({ReviewRating rating, bool correct, int dayOffset, int durationMs})>
    script,
  ) async {
    for (final (index, step) in script.indexed) {
      final now = start + step.dayOffset * dayMs;
      await service.processAnswer(
        AnswerInput(
          clientAnswerId: 'answer-$wordId-$index',
          wordId: wordId,
          rating: step.rating,
          questionType: QuestionType.zhToEnSpelling,
          userAnswer: 'apple',
          durationMs: step.durationMs,
        ),
        now: now,
      );
    }
  }

  /// 从库里读回流水，构造重放输入（按 reviewed_at 升序）。
  Future<List<ReplayLog>> logsOf(int wordId) async {
    final rows = await db
        .customSelect(
          'SELECT reviewed_at, rating, is_correct, duration_ms '
          'FROM review_logs WHERE word_id = ? ORDER BY reviewed_at ASC, '
          'client_answer_id ASC',
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .get();
    return rows.map((row) => replayLogFromRow(row.data)).toList();
  }

  /// 从库里读回流水线写下的卡片。
  Future<ReviewCardRow> cardOf(int wordId) => (db.select(
    db.reviewCards,
  )..where((row) => row.wordId.equals(wordId))).getSingle();

  /// 从库里读回流水线写下的错词状态（可能没有）。
  Future<WrongWordStateRow?> wrongOf(int wordId) => (db.select(
    db.wrongWordStates,
  )..where((row) => row.wordId.equals(wordId))).getSingleOrNull();

  /// 从库里读回流水线写下的熟练度。
  Future<WordRow> wordRowOf(int wordId) =>
      (db.select(db.words)..where((row) => row.id.equals(wordId))).getSingle();

  /// 拿重放结果与库里的实际值逐字段比对。
  ///
  /// [now] 传**最后一次作答的时间**：流水线的 14/30 天窗口就是按它算的，
  /// 重放必须用同一个基准才能逐字段相等。
  Future<void> expectReplayMatches(int wordId, {required int now}) async {
    final logs = await logsOf(wordId);
    final replayed = replayWordHistory(
      logs: logs,
      scheduler: scheduler,
      now: now,
    );

    final card = await cardOf(wordId);
    expect(replayed.card.dueAt, card.dueAt, reason: 'due_at');
    expect(replayed.card.stability, card.stability, reason: 'stability');
    expect(replayed.card.difficulty, card.difficulty, reason: 'difficulty');
    expect(replayed.card.elapsedDays, card.elapsedDays, reason: 'elapsed_days');
    expect(
      replayed.card.scheduledDays,
      card.scheduledDays,
      reason: 'scheduled_days',
    );
    expect(replayed.card.reps, card.reps, reason: 'reps');
    expect(replayed.card.lapses, card.lapses, reason: 'lapses');
    expect(replayed.card.fsrsState, card.fsrsState, reason: 'fsrs_state');
    expect(
      replayed.card.learningSteps,
      card.learningSteps,
      reason: 'learning_steps',
    );
    expect(
      replayed.card.lastReviewAt,
      card.lastReviewAt,
      reason: 'last_review_at',
    );

    final wrong = await wrongOf(wordId);
    final replayedWrong = replayed.wrong;
    if (replayedWrong == null) {
      expect(wrong, isNull, reason: '重放认为没有错词记录，库里也不该有');
    } else {
      expect(wrong, isNotNull, reason: '重放认为错词记录存在，库里却没有');
      expect(replayedWrong.active, wrong!.active, reason: 'wrong.active');
      expect(replayedWrong.wrongCount, wrong.wrongCount, reason: 'wrong_count');
      expect(replayedWrong.hardCount, wrong.hardCount, reason: 'hard_count');
      expect(
        replayedWrong.consecutiveCorrect,
        wrong.consecutiveCorrect,
        reason: 'consecutive_correct',
      );
      expect(
        replayedWrong.lastWrongAt,
        wrong.lastWrongAt,
        reason: 'last_wrong_at',
      );
      expect(
        replayedWrong.lastCorrectAt,
        wrong.lastCorrectAt,
        reason: 'last_correct_at',
      );
      expect(replayedWrong.resolvedAt, wrong.resolvedAt, reason: 'resolved_at');
    }

    final word = await wordRowOf(wordId);
    expect(replayed.masteryScore, word.masteryScore, reason: 'mastery_score');
    expect(replayed.masteryLevel, word.masteryLevel, reason: 'mastery_level');
  }

  test('单次作答：卡片、错词、熟练度全部一致', () async {
    final wordId = await insertWord('apple');
    await answerSeries(
      wordId,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 0,
          durationMs: 3000,
        ),
      ],
    );

    await expectReplayMatches(wordId, now: start);
  });

  test('四级评级各来一次：卡片与错词全部一致', () async {
    final wordId = await insertWord('apple');
    await answerSeries(
      wordId,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 0,
          durationMs: 3000,
        ),
        (
          rating: ReviewRating.hard,
          correct: true,
          dayOffset: 1,
          durationMs: 6000,
        ),
        (
          rating: ReviewRating.again,
          correct: false,
          dayOffset: 3,
          durationMs: 9000,
        ),
        (
          rating: ReviewRating.easy,
          correct: true,
          dayOffset: 12,
          durationMs: 1200,
        ),
      ],
    );

    await expectReplayMatches(wordId, now: start + 12 * dayMs);
  });

  test('连续多日的「记得」会把错词解除，重放同样解除', () async {
    final wordId = await insertWord('apple');
    await answerSeries(
      wordId,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        // 先错一次，进错词本。
        (
          rating: ReviewRating.again,
          correct: false,
          dayOffset: 0,
          durationMs: 4000,
        ),
        // 然后连续三个自然日答对，达到解除条件。
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 1,
          durationMs: 3000,
        ),
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 2,
          durationMs: 3000,
        ),
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 3,
          durationMs: 3000,
        ),
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 4,
          durationMs: 3000,
        ),
      ],
    );

    await expectReplayMatches(wordId, now: start + 4 * dayMs);
  });

  test('同一天内重复答对不会累加连续天数（自然日规则）', () async {
    final wordId = await insertWord('apple');
    await answerSeries(
      wordId,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        (
          rating: ReviewRating.again,
          correct: false,
          dayOffset: 0,
          durationMs: 4000,
        ),
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 1,
          durationMs: 3000,
        ),
        // 同一天下午再答对两次。
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 1,
          durationMs: 3000,
        ),
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 1,
          durationMs: 3000,
        ),
      ],
    );

    await expectReplayMatches(wordId, now: start + dayMs);
  });

  test('没有有效耗时的流水：平均耗时为 null，熟练度仍然一致', () async {
    final wordId = await insertWord('apple');
    await answerSeries(
      wordId,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        (rating: ReviewRating.good, correct: true, dayOffset: 0, durationMs: 0),
        (rating: ReviewRating.good, correct: true, dayOffset: 1, durationMs: 0),
      ],
    );

    final logs = await logsOf(wordId);
    final replayed = replayWordHistory(
      logs: logs,
      scheduler: scheduler,
      now: start + dayMs,
    );
    expect(replayed.stats.averageDurationMs, isNull);
    await expectReplayMatches(wordId, now: start + dayMs);
  });

  test('「自评记得但答错」被降级成 AGAIN，重放按日志里的评级走', () async {
    final wordId = await insertWord('apple');
    await service.processAnswer(
      AnswerInput(
        clientAnswerId: 'downgraded-1',
        wordId: wordId,
        rating: ReviewRating.good,
        questionType: QuestionType.zhToEnSpelling,
        // 答案明显不对：会被判错并降级。
        userAnswer: 'banana',
        durationMs: 5000,
      ),
      now: start,
    );

    final logs = await logsOf(wordId);
    expect(
      logs.single.rating,
      ReviewRating.again,
      reason: '流水线应当把「记得但答错」降级成 AGAIN 再写日志',
    );
    await expectReplayMatches(wordId, now: start);
  });

  test('多个词互不影响：各自的流水独立重放', () async {
    final apple = await insertWord('apple');
    final banana = await insertWord('banana');
    await answerSeries(
      apple,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 0,
          durationMs: 3000,
        ),
        (
          rating: ReviewRating.again,
          correct: false,
          dayOffset: 2,
          durationMs: 8000,
        ),
      ],
    );
    await answerSeries(
      banana,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        (
          rating: ReviewRating.easy,
          correct: true,
          dayOffset: 1,
          durationMs: 2000,
        ),
      ],
    );

    await expectReplayMatches(apple, now: start + 2 * dayMs);
    await expectReplayMatches(banana, now: start + 2 * dayMs);
  });

  test('30 天窗口：窗口外的 AGAIN 不进 recentAgain', () async {
    final wordId = await insertWord('apple');
    await answerSeries(
      wordId,
      <({ReviewRating rating, bool correct, int dayOffset, int durationMs})>[
        // 40 天前的 AGAIN 在窗口外。
        (
          rating: ReviewRating.again,
          correct: false,
          dayOffset: -40,
          durationMs: 4000,
        ),
        (
          rating: ReviewRating.good,
          correct: true,
          dayOffset: 0,
          durationMs: 3000,
        ),
      ],
    );

    final logs = await logsOf(wordId);
    final replayed = replayWordHistory(
      logs: logs,
      scheduler: scheduler,
      now: start,
    );
    expect(replayed.stats.recentAgain, 0);
    expect(replayed.stats.total, 2);
    await expectReplayMatches(wordId, now: start);
  });

  test('空流水被明确拒绝，而不是算出一张空卡', () {
    expect(
      () => replayWordHistory(
        logs: const <ReplayLog>[],
        scheduler: scheduler,
        now: start,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('未知评级报错而不是猜一个默认值', () {
    expect(
      () => replayLogFromRow(<String, Object?>{
        'reviewed_at': start,
        'rating': 'PERFECT',
        'is_correct': 1,
      }),
      throwsA(isA<Exception>()),
    );
  });

  test('布尔在 0/1 与 true/false 两种来源下等价', () {
    final fromSql = replayLogFromRow(<String, Object?>{
      'reviewed_at': start,
      'rating': ReviewRating.good.wire,
      'is_correct': 1,
      'duration_ms': 3000,
    });
    final fromJson = replayLogFromRow(<String, Object?>{
      'reviewed_at': start,
      'rating': ReviewRating.good.wire,
      'is_correct': true,
      'duration_ms': 3000,
    });
    expect(fromSql.isCorrect, isTrue);
    expect(fromJson.isCorrect, isTrue);
    expect(fromSql.rating, fromJson.rating);
    expect(fromSql.durationMs, fromJson.durationMs);
  });
}
