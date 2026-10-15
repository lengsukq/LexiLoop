/// 复习 DAO 的单元测试。
///
/// 这一层承载「一次作答的原子写入」：卡片推进、日志落盘、统计窗口重算、
/// 熟练度与会话收尾。旧版这些逻辑塞在 PostgreSQL 数据修改 CTE 里，
/// 出错时只能靠肉眼看 SQL；拆开后这里逐条钉住行为。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/review_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';

void main() {
  late AppDatabase db;
  late ReviewDao dao;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = ReviewDao(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一条 READY 的词条，返回其 id。
  Future<int> insertWord({
    String term = 'apple',
    String? definitionsJson = '[{"language":"zh","text":"苹果"}]',
    InitializationStatus status = InitializationStatus.ready,
    bool isSuspended = false,
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
            initializationStatus: Value<InitializationStatus>(status),
            isSuspended: Value<bool>(isSuspended),
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (definitionsJson != null) {
      await db
          .into(db.wordContents)
          .insert(
            WordContentsCompanion.insert(
              wordId: Value<int>(id),
              definitionsJson: Value<String>(definitionsJson),
              updatedAt: now,
            ),
          );
    }
    return id;
  }

  /// 建一个未完成的学习会话，返回其 id。
  Future<int> insertSession({int plannedCount = 2}) => db
      .into(db.studySessions)
      .insert(
        StudySessionsCompanion.insert(
          sessionType: StudyMode.daily,
          startedAt: now,
          plannedCount: Value<int>(plannedCount),
          createdAt: now,
        ),
      );

  /// 建一道 PENDING 的题目，返回其 id。
  Future<int> insertItem(
    int sessionId,
    int wordId, {
    double position = 0,
    QuestionType questionType = QuestionType.zhToEnSpelling,
  }) => db
      .into(db.studySessionItems)
      .insert(
        StudySessionItemsCompanion.insert(
          studySessionId: sessionId,
          position: position,
          wordId: wordId,
          taskType: StudyTaskType.review,
          questionType: questionType,
          createdAt: now,
        ),
      );

  ReviewCardState card({
    int? dueAt,
    double stability = 1,
    int reps = 1,
    int scheduledDays = 1,
  }) => ReviewCardState(
    dueAt: dueAt ?? now + dayMs,
    stability: stability,
    difficulty: 5,
    elapsedDays: 0,
    scheduledDays: scheduledDays,
    reps: reps,
    lapses: 0,
    fsrsState: 1,
    learningSteps: 0,
    lastReviewAt: now,
  );

  AnswerInput answer({
    required int wordId,
    String clientAnswerId = 'c1',
    int? sessionId,
    int? itemId,
    QuestionType questionType = QuestionType.zhToEnSpelling,
    ReviewRating rating = ReviewRating.good,
    String? userAnswer = 'apple',
    int? durationMs = 3000,
  }) => AnswerInput(
    clientAnswerId: clientAnswerId,
    wordId: wordId,
    rating: rating,
    questionType: questionType,
    studySessionId: sessionId,
    studySessionItemId: itemId,
    userAnswer: userAnswer,
    durationMs: durationMs,
  );

  group('findExistingLog', () {
    test('未写入时返回 null', () async {
      expect(await dao.findExistingLog('missing'), isNull);
    });

    test('写入后能按幂等键读回', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );

      final existing = await dao.findExistingLog('c1');
      expect(existing, isNotNull);
      expect(existing!.wordId, wordId);
      expect(existing.rating, ReviewRating.good);
      expect(existing.isCorrect, isTrue);
      expect(existing.expectedAnswer, '苹果');
      expect(existing.studySessionId, isNull);
    });

    test('同一幂等键不能写两次（唯一索引兜底）', () async {
      final wordId = await insertWord();
      Future<void> write() => dao.insertCardAndLog(
        answer: answer(wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );
      await write();
      await expectLater(write(), throwsA(isA<Exception>()));
    });
  });

  group('findContext', () {
    test('词条不存在时三个字段都为 null', () async {
      final context = await dao.findContext(9999);
      expect(context.word, isNull);
      expect(context.card, isNull);
      expect(context.wrongState, isNull);
    });

    test('首次复习时卡片与错词状态为空', () async {
      final wordId = await insertWord();
      final context = await dao.findContext(wordId);
      expect(context.word?.term, 'apple');
      expect(context.word?.definitionsJson, contains('苹果'));
      expect(context.card, isNull);
      expect(context.wrongState, isNull);
    });

    test('写入卡片与错词状态后能读回', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.again,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: false,
        before: card(),
        after: card(reps: 2, scheduledDays: 3),
        now: now,
      );
      await db
          .into(db.wrongWordStates)
          .insert(
            WrongWordStatesCompanion.insert(
              wordId: Value<int>(wordId),
              active: const Value<bool>(true),
              wrongCount: const Value<int>(2),
              updatedAt: now,
            ),
          );

      final context = await dao.findContext(wordId);
      expect(context.card?.reps, 2);
      expect(context.card?.scheduledDays, 3);
      expect(context.wrongState?.active, isTrue);
      expect(context.wrongState?.wrongCount, 2);
    });

    test('已暂停的词条仍能被读出，可复习性由领域层判断', () async {
      final wordId = await insertWord(isSuspended: true);
      final context = await dao.findContext(wordId);
      expect(context.word?.isSuspended, isTrue);
      expect(context.word?.isReviewable, isFalse);
    });

    test('未就绪的词条不可复习', () async {
      final wordId = await insertWord(status: InitializationStatus.pending);
      final context = await dao.findContext(wordId);
      expect(context.word?.isReviewable, isFalse);
    });
  });

  group('claimStudyItem', () {
    test('成功认领后题目变为 ANSWERED', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession();
      final itemId = await insertItem(sessionId, wordId);

      await dao.claimStudyItem(
        sessionId: sessionId,
        itemId: itemId,
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
        now: now,
      );

      final item = await (db.select(
        db.studySessionItems,
      )..where((row) => row.id.equals(itemId))).getSingle();
      expect(item.status, StudyItemStatus.answered);
      expect(item.answeredAt, now);
    });

    test('重复认领抛出「已处理」冲突', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession();
      final itemId = await insertItem(sessionId, wordId);
      Future<void> claim() => dao.claimStudyItem(
        sessionId: sessionId,
        itemId: itemId,
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
        now: now,
      );
      await claim();
      await expectLater(claim(), throwsA(isA<Exception>()));
    });

    test('题目不存在时报「不存在」而不是笼统失败', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession();
      await expectLater(
        dao.claimStudyItem(
          sessionId: sessionId,
          itemId: 9999,
          wordId: wordId,
          questionType: QuestionType.zhToEnSpelling,
          now: now,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('词条不匹配与题型不匹配分别报错', () async {
      final wordId = await insertWord();
      final otherId = await insertWord(term: 'banana');
      final sessionId = await insertSession();
      final itemId = await insertItem(sessionId, wordId);

      await expectLater(
        dao.claimStudyItem(
          sessionId: sessionId,
          itemId: itemId,
          wordId: otherId,
          questionType: QuestionType.zhToEnSpelling,
          now: now,
        ),
        throwsA(isA<Exception>()),
      );
      await expectLater(
        dao.claimStudyItem(
          sessionId: sessionId,
          itemId: itemId,
          wordId: wordId,
          questionType: QuestionType.enToZhChoice,
          now: now,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('会话已完成时不能认领', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession();
      final itemId = await insertItem(sessionId, wordId);
      await (db.update(db.studySessions)
            ..where((row) => row.id.equals(sessionId)))
          .write(StudySessionsCompanion(completedAt: Value<int>(now)));

      await expectLater(
        dao.claimStudyItem(
          sessionId: sessionId,
          itemId: itemId,
          wordId: wordId,
          questionType: QuestionType.zhToEnSpelling,
          now: now,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('upsertWordReviewStats', () {
    test('首次写入建立统计行', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );

      final stats = await dao.upsertWordReviewStats(
        wordId: wordId,
        reviewedAt: now,
        isCorrect: true,
        durationMs: 4000,
      );
      expect(stats.total, 1);
      expect(stats.correct, 1);
      expect(stats.recentAgain, 0);
      expect(stats.averageDurationMs, 4000);
    });

    test('生命周期计数累加，平均耗时按有效样本计算', () async {
      final wordId = await insertWord();
      for (final (index, duration) in <int?>[2000, 4000, null].indexed) {
        await dao.insertCardAndLog(
          answer: answer(
            clientAnswerId: 'c$index',
            wordId: wordId,
            durationMs: duration,
          ),
          reviewedAt: now + index,
          rating: ReviewRating.good,
          presentedPrompt: 'apple',
          expectedAnswer: '苹果',
          isCorrect: true,
          before: card(),
          after: card(),
          now: now + index,
        );
        await dao.upsertWordReviewStats(
          wordId: wordId,
          reviewedAt: now + index,
          isCorrect: true,
          durationMs: duration,
        );
      }

      final stats = await dao.loadStatistics(wordId);
      expect(stats.total, 3);
      expect(stats.correct, 3);
      // 只有两次有有效耗时：(2000 + 4000) / 2 = 3000。
      expect(stats.averageDurationMs, 3000);
    });

    test('窗口计数只统计窗口内的记录', () async {
      final wordId = await insertWord();
      // 一条 40 天前的 AGAIN（在 30 天窗口之外），一条今天的 AGAIN。
      final old = now - 40 * dayMs;
      await dao.insertCardAndLog(
        answer: answer(clientAnswerId: 'old', wordId: wordId),
        reviewedAt: old,
        rating: ReviewRating.again,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: false,
        before: card(),
        after: card(),
        now: old,
      );
      await dao.insertCardAndLog(
        answer: answer(clientAnswerId: 'new', wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.again,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: false,
        before: card(),
        after: card(),
        now: now,
      );

      final stats = await dao.upsertWordReviewStats(
        wordId: wordId,
        reviewedAt: now,
        isCorrect: false,
        durationMs: null,
      );
      expect(stats.recentAgain, 1, reason: '40 天前的 AGAIN 不应计入 30 天窗口');
      // 生命周期计数按调用次数累加（真实流程里每次作答调一次），
      // 窗口计数则是按日志重算的。
      expect(stats.total, 1);
    });

    test('HARD 与答错分别计入不同窗口列', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(clientAnswerId: 'h1', wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.hard,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );
      await dao.upsertWordReviewStats(
        wordId: wordId,
        reviewedAt: now,
        isCorrect: true,
        durationMs: null,
      );

      final row = await db
          .customSelect(
            'SELECT recent_hard_14d, recent_wrong_14d, recent_again_14d '
            'FROM word_review_stats WHERE word_id = ?',
            variables: <Variable<Object>>[Variable<int>(wordId)],
          )
          .getSingle();
      expect(row.read<int>('recent_hard_14d'), 1);
      expect(row.read<int>('recent_wrong_14d'), 0);
      expect(row.read<int>('recent_again_14d'), 0);
    });

    test('没有统计行时按日志现算', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );

      final stats = await dao.loadStatistics(wordId);
      expect(stats.total, 1);
      expect(stats.correct, 1);
      expect(stats.averageDurationMs, 3000);
    });

    test('完全没有记录时返回零值', () async {
      final wordId = await insertWord();
      final stats = await dao.loadStatistics(wordId);
      expect(stats.total, 0);
      expect(stats.accuracy, 0);
      expect(stats.averageDurationMs, isNull);
    });
  });

  group('updateMastery', () {
    test('写入熟练分与等级', () async {
      final wordId = await insertWord();
      await dao.updateMastery(wordId, 77, MasteryLevel.proficient, now);

      final word = await (db.select(
        db.words,
      )..where((row) => row.id.equals(wordId))).getSingle();
      expect(word.masteryScore, 77);
      expect(word.masteryLevel, MasteryLevel.proficient);
      expect(word.updatedAt, now);
    });
  });

  group('finalizeSession', () {
    test('还有待答题目时不收尾', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession();
      await insertItem(sessionId, wordId);
      await insertItem(sessionId, wordId, position: 1);

      await dao.finalizeSession(
        sessionId: sessionId,
        isCorrect: true,
        now: now,
      );

      final session = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
      expect(session.completedCount, 1);
      expect(session.correctCount, 1);
      expect(session.wrongCount, 0);
      expect(session.completedAt, isNull);
    });

    test('没有待答题目时收尾并回填有效时长', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession(plannedCount: 1);
      final itemId = await insertItem(sessionId, wordId);
      await dao.claimStudyItem(
        sessionId: sessionId,
        itemId: itemId,
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
        now: now,
      );
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId, sessionId: sessionId, itemId: itemId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );

      await dao.finalizeSession(
        sessionId: sessionId,
        isCorrect: true,
        now: now + 5000,
      );

      final session = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
      expect(session.completedAt, now + 5000);
      expect(session.durationMs, 3000);
    });

    test('挂机时长按上限计入，不污染统计', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession(plannedCount: 1);
      final itemId = await insertItem(sessionId, wordId);
      await dao.claimStudyItem(
        sessionId: sessionId,
        itemId: itemId,
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
        now: now,
      );
      await dao.insertCardAndLog(
        answer: answer(
          wordId: wordId,
          sessionId: sessionId,
          itemId: itemId,
          durationMs: maxActiveAnswerDurationMs * 100,
        ),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );

      await dao.finalizeSession(
        sessionId: sessionId,
        isCorrect: true,
        now: now,
      );

      final session = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
      expect(session.durationMs, maxActiveAnswerDurationMs);
    });

    test('答错时计入 wrong_count', () async {
      final sessionId = await insertSession();

      await dao.finalizeSession(
        sessionId: sessionId,
        isCorrect: false,
        now: now,
      );

      final session = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
      expect(session.wrongCount, 1);
      expect(session.correctCount, 0);
    });
  });

  group('pendingItemCount', () {
    test('统计未作答题目', () async {
      final wordId = await insertWord();
      final sessionId = await insertSession();
      await insertItem(sessionId, wordId);
      final second = await insertItem(sessionId, wordId, position: 1);
      expect(await dao.pendingItemCount(sessionId), 2);

      await dao.claimStudyItem(
        sessionId: sessionId,
        itemId: second,
        wordId: wordId,
        questionType: QuestionType.zhToEnSpelling,
        now: now,
      );
      expect(await dao.pendingItemCount(sessionId), 1);
    });
  });

  group('insertCardAndLog', () {
    test('卡片快照与日志快照都被记录', () async {
      final wordId = await insertWord();
      final before = card();
      final after = card(reps: 2, stability: 9.5, scheduledDays: 6);
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: before,
        after: after,
        now: now,
      );

      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.cardBeforeJson, contains('"reps":1'));
      expect(log.cardAfterJson, contains('"reps":2'));
      expect(log.cardAfterJson, contains('"stability":9.5'));
      expect(log.presentedPrompt, 'apple');
      expect(log.expectedAnswer, '苹果');
      expect(log.userAnswer, 'apple');
      expect(log.durationMs, 3000);
    });

    test('负耗时被夹到 0，超长耗时被夹到上限', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId, durationMs: -100),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );
      var log = await db.select(db.reviewLogs).getSingle();
      expect(log.durationMs, 0);

      await dao.insertCardAndLog(
        answer: answer(
          clientAnswerId: 'c2',
          wordId: wordId,
          durationMs: maxActiveAnswerDurationMs * 10,
        ),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );
      log = await (db.select(
        db.reviewLogs,
      )..where((row) => row.clientAnswerId.equals('c2'))).getSingle();
      expect(log.durationMs, maxActiveAnswerDurationMs);
    });

    test('未提供耗时记为 null 而不是 0', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId, durationMs: null),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );
      final log = await db.select(db.reviewLogs).getSingle();
      expect(log.durationMs, isNull);
    });

    test('卡片按 word_id 覆盖写入，不会重复建行', () async {
      final wordId = await insertWord();
      await dao.insertCardAndLog(
        answer: answer(clientAnswerId: 'a', wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(),
        now: now,
      );
      await dao.insertCardAndLog(
        answer: answer(clientAnswerId: 'b', wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: card(reps: 2, scheduledDays: 9),
        now: now,
      );

      final cards = await db.select(db.reviewCards).get();
      expect(cards.length, 1);
      expect(cards.single.reps, 2);
      expect(cards.single.scheduledDays, 9);
    });
  });

  group('findCard', () {
    test('未写入时返回 null', () async {
      final wordId = await insertWord();
      expect(await dao.findCard(wordId), isNull);
    });

    test('写入后读回全部字段', () async {
      final wordId = await insertWord();
      final state = card(reps: 4, stability: 12.5, scheduledDays: 30);
      await dao.insertCardAndLog(
        answer: answer(wordId: wordId),
        reviewedAt: now,
        rating: ReviewRating.good,
        presentedPrompt: 'apple',
        expectedAnswer: '苹果',
        isCorrect: true,
        before: card(),
        after: state,
        now: now,
      );

      final read = await dao.findCard(wordId);
      expect(read, isNotNull);
      expect(read!.reps, state.reps);
      expect(read.stability, state.stability);
      expect(read.scheduledDays, state.scheduledDays);
      expect(read.fsrsState, state.fsrsState);
      expect(read.learningSteps, state.learningSteps);
      expect(read.lastReviewAt, state.lastReviewAt);
    });
  });

  group('卡片快照 JSON', () {
    test('字段名与旧版 ts-fsrs 的 Card 对齐', () {
      final json = card(reps: 3, scheduledDays: 7).toJson();
      for (final key in <String>[
        '"due"',
        '"stability"',
        '"difficulty"',
        '"elapsed_days"',
        '"scheduled_days"',
        '"reps"',
        '"lapses"',
        '"state"',
        '"learning_steps"',
        '"last_review"',
      ]) {
        expect(json, contains(key));
      }
    });

    test('lastReviewAt 为 null 时输出 JSON null', () {
      final state = ReviewCardState(
        dueAt: now,
        stability: 1,
        difficulty: 5,
        elapsedDays: 0,
        scheduledDays: 1,
        reps: 1,
        lapses: 0,
        fsrsState: 1,
        learningSteps: 0,
        lastReviewAt: null,
      );
      expect(state.toJson(), contains('"last_review":null'));
    });
  });
}
