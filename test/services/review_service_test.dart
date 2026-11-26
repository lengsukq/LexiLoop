/// 作答流水线的集成测试。
///
/// 这里验证的是**跨模块协作**：认领题目 → 判题 → FSRS → 日志 → 统计 →
/// 错词 → 熟练度 → 插题 → 收尾。单个模块各自的单测在别处，
/// 本文件关注的是「接起来之后行为是否仍然正确」。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/services/review_service.dart';
import 'package:lexiloop/services/settings_service.dart';

void main() {
  late AppDatabase db;
  late ReviewService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = ReviewService(db, SettingsService(SettingsDao(db)));
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

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

  /// 建一个含 [wordCount] 道题的会话，返回 (sessionId, 题目 ID 列表)。
  Future<(int, List<int>)> insertSession({
    int wordCount = 3,
    StudyMode mode = StudyMode.daily,
    String? sourceType,
    QuestionType questionType = QuestionType.zhToEnSpelling,
  }) async {
    final sessionId = await db
        .into(db.studySessions)
        .insert(
          StudySessionsCompanion.insert(
            sessionType: mode,
            sourceType: Value<String?>(sourceType),
            startedAt: now,
            plannedCount: Value<int>(wordCount),
            createdAt: now,
          ),
        );
    final itemIds = <int>[];
    for (var index = 0; index < wordCount; index += 1) {
      final wordId = await insertWord(term: 'word$index');
      itemIds.add(
        await db
            .into(db.studySessionItems)
            .insert(
              StudySessionItemsCompanion.insert(
                studySessionId: sessionId,
                position: index.toDouble(),
                wordId: wordId,
                taskType: StudyTaskType.review,
                questionType: questionType,
                createdAt: now,
              ),
            ),
      );
    }
    return (sessionId, itemIds);
  }

  /// 读取会话内的题目行。
  Future<List<StudySessionItemRow>> itemsOf(int sessionId) =>
      (db.select(db.studySessionItems)
            ..where((row) => row.studySessionId.equals(sessionId))
            ..orderBy(<OrderClauseGenerator<$StudySessionItemsTable>>[
              (row) => OrderingTerm.asc(row.position),
            ]))
          .get();

  Future<StudySessionRow> sessionOf(int sessionId) => (db.select(
    db.studySessions,
  )..where((row) => row.id.equals(sessionId))).getSingle();

  AnswerInput answer({
    required int wordId,
    String clientAnswerId = 'c1',
    int? sessionId,
    int? itemId,
    ReviewRating rating = ReviewRating.good,
    QuestionType questionType = QuestionType.zhToEnSpelling,
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

  group('首次作答', () {
    test('建立卡片、日志、统计与熟练度', () async {
      final wordId = await insertWord();

      final outcome = await service.processAnswer(
        answer(wordId: wordId),
        now: now,
      );

      expect(outcome.idempotent, isFalse);
      expect(outcome.isCorrect, isTrue);
      expect(outcome.rating, ReviewRating.good);
      expect(outcome.nextDueAt, isNotNull);
      expect(outcome.scheduledDays, 0, reason: '新卡首次 GOOD 仍在学习步内');
      expect(outcome.wrongWordActive, isFalse);

      expect(await db.select(db.reviewLogs).get(), hasLength(1));
      expect(await db.select(db.reviewCards).get(), hasLength(1));
      expect(await db.select(db.wordReviewStats).get(), hasLength(1));

      final word = await (db.select(
        db.words,
      )..where((row) => row.id.equals(wordId))).getSingle();
      expect(word.masteryScore, outcome.masteryScore);
      expect(word.masteryLevel, outcome.masteryLevel);
      expect(word.masteryScore, greaterThan(0));
    });

    test('答错时进入错词本并把等级降为 AGAIN', () async {
      final wordId = await insertWord();

      final outcome = await service.processAnswer(
        answer(wordId: wordId, userAnswer: 'banana'),
        now: now,
      );

      expect(outcome.isCorrect, isFalse);
      expect(outcome.rating, ReviewRating.again);
      expect(outcome.wrongWordActive, isTrue);

      final wrong = await db.select(db.wrongWordStates).getSingle();
      expect(wrong.active, isTrue);
      expect(wrong.wrongCount, 1);
      expect(wrong.consecutiveCorrect, 0);
    });

    test('答对时不写错词行，避免为从没错过的词留噪声', () async {
      final wordId = await insertWord();
      await service.processAnswer(answer(wordId: wordId), now: now);
      expect(await db.select(db.wrongWordStates).get(), isEmpty);
    });

    test('主观题（看英选中）采信自评', () async {
      final wordId = await insertWord();
      final outcome = await service.processAnswer(
        answer(
          wordId: wordId,
          questionType: QuestionType.enToZh,
          userAnswer: null,
        ),
        now: now,
      );
      expect(outcome.isCorrect, isTrue);
    });

    test('未就绪的词条被拒绝', () async {
      final wordId = await insertWord(status: InitializationStatus.pending);
      await expectLater(
        service.processAnswer(answer(wordId: wordId), now: now),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.wordNotReady,
          ),
        ),
      );
    });

    test('已暂停的词条被拒绝', () async {
      final wordId = await insertWord(isSuspended: true);
      await expectLater(
        service.processAnswer(answer(wordId: wordId), now: now),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.wordSuspended,
          ),
        ),
      );
    });

    test('不存在的词条被拒绝', () async {
      await expectLater(
        service.processAnswer(answer(wordId: 9999), now: now),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.wordNotFound,
          ),
        ),
      );
    });
  });

  group('幂等', () {
    test('重复提交同一幂等键只产生一条日志', () async {
      final wordId = await insertWord();
      final input = answer(wordId: wordId);

      final first = await service.processAnswer(input, now: now);
      final second = await service.processAnswer(input, now: now + 60000);

      expect(first.idempotent, isFalse);
      expect(second.idempotent, isTrue);
      expect(second.reviewLogId, first.reviewLogId);
      expect(second.masteryScore, first.masteryScore);
      expect(await db.select(db.reviewLogs).get(), hasLength(1));
    });

    test('幂等回显不会二次推进 FSRS', () async {
      final wordId = await insertWord();
      final input = answer(wordId: wordId);
      await service.processAnswer(input, now: now);
      final cardAfterFirst = await db.select(db.reviewCards).getSingle();

      await service.processAnswer(input, now: now + dayMs);

      final cardAfterSecond = await db.select(db.reviewCards).getSingle();
      expect(cardAfterSecond.reps, cardAfterFirst.reps);
      expect(cardAfterSecond.dueAt, cardAfterFirst.dueAt);
    });

    test('同一幂等键换了词条时报冲突', () async {
      final firstWord = await insertWord();
      final secondWord = await insertWord(term: 'banana');
      await service.processAnswer(
        answer(wordId: firstWord, clientAnswerId: 'same'),
        now: now,
      );

      await expectLater(
        service.processAnswer(
          answer(wordId: secondWord, clientAnswerId: 'same'),
          now: now,
        ),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.idempotencyKeyConflict,
          ),
        ),
      );
    });
  });

  group('会话内作答', () {
    test('认领题目并把会话收尾', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 1);
      final item = await (db.select(
        db.studySessionItems,
      )..where((row) => row.id.equals(itemIds.single))).getSingle();

      await service.processAnswer(
        answer(
          wordId: item.wordId,
          sessionId: sessionId,
          itemId: itemIds.single,
          userAnswer: 'word0',
        ),
        now: now,
      );

      final updated = await (db.select(
        db.studySessionItems,
      )..where((row) => row.id.equals(itemIds.single))).getSingle();
      expect(updated.status, StudyItemStatus.answered);

      final session = await sessionOf(sessionId);
      expect(session.completedCount, 1);
      expect(session.correctCount, 1);
      expect(session.completedAt, now);
    });

    test('还有待答题目时不收尾会话', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 2);
      final items = await itemsOf(sessionId);

      await service.processAnswer(
        answer(
          wordId: items.first.wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          userAnswer: 'word0',
        ),
        now: now,
      );

      final session = await sessionOf(sessionId);
      expect(session.completedAt, isNull);
      expect(session.completedCount, 1);
    });

    test('题目已被处理时拒绝重复认领', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 1);
      final item = await (db.select(
        db.studySessionItems,
      )..where((row) => row.id.equals(itemIds.single))).getSingle();
      final input = answer(
        wordId: item.wordId,
        sessionId: sessionId,
        itemId: itemIds.single,
        userAnswer: 'word0',
      );
      await service.processAnswer(input, now: now);

      // 换一个幂等键重放同一道题：应被「已处理」拦下。
      await expectLater(
        service.processAnswer(
          answer(
            wordId: item.wordId,
            clientAnswerId: 'another',
            sessionId: sessionId,
            itemId: itemIds.single,
            userAnswer: 'word0',
          ),
          now: now,
        ),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('自适应插题', () {
    test('答错且后面还有足够题量时插入追问题', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 12);
      final items = await itemsOf(sessionId);
      final target = items.first;

      final outcome = await service.processAnswer(
        answer(
          wordId: target.wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          userAnswer: 'wrong',
        ),
        now: now,
      );

      expect(outcome.adaptiveFollowUp, isNotNull);
      expect(outcome.adaptiveFollowUp!.repetition, 0);

      final after = await itemsOf(sessionId);
      expect(after, hasLength(13));
      expect((await sessionOf(sessionId)).plannedCount, 13);

      final followUp = after.firstWhere(
        (row) => row.taskType == StudyTaskType.wrong,
      );
      expect(followUp.wordId, target.wordId);
      expect(followUp.status, StudyItemStatus.pending);
      // 插入位置应落在当前题之后、第 5 题之前。
      expect(followUp.position, greaterThan(target.position));
      expect(followUp.position, lessThan(items[5].position));
    });

    test('答对时不插题', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 12);
      final items = await itemsOf(sessionId);

      final outcome = await service.processAnswer(
        answer(
          wordId: items.first.wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          userAnswer: 'word0',
        ),
        now: now,
      );

      expect(outcome.adaptiveFollowUp, isNull);
      expect(await itemsOf(sessionId), hasLength(12));
    });

    test('评为「模糊」时不插题（已进错词本，交给后续会话）', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 12);
      final items = await itemsOf(sessionId);

      final outcome = await service.processAnswer(
        answer(
          wordId: items.first.wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          rating: ReviewRating.hard,
          userAnswer: 'wrong',
        ),
        now: now,
      );

      expect(outcome.adaptiveFollowUp, isNull);
      expect(outcome.wrongWordActive, isTrue);
    });

    test('游戏会话不插题', () async {
      final (sessionId, itemIds) = await insertSession(
        wordCount: 12,
        mode: StudyMode.wrongWords,
        sourceType: 'GAME_TETRIS',
      );
      final items = await itemsOf(sessionId);

      final outcome = await service.processAnswer(
        answer(
          wordId: items.first.wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          userAnswer: 'wrong',
        ),
        now: now,
      );

      expect(outcome.adaptiveFollowUp, isNull);
      expect(await itemsOf(sessionId), hasLength(12));
    });

    test('已有一道待答的追问题时不再叠加', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 12);
      final items = await itemsOf(sessionId);
      final wordId = items.first.wordId;

      // 预置一道同词的 PENDING 追问题。
      await db
          .into(db.studySessionItems)
          .insert(
            StudySessionItemsCompanion.insert(
              studySessionId: sessionId,
              position: 0.5,
              wordId: wordId,
              taskType: StudyTaskType.wrong,
              questionType: QuestionType.zhToEnSpelling,
              createdAt: now,
            ),
          );

      final outcome = await service.processAnswer(
        answer(
          wordId: wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          userAnswer: 'wrong',
        ),
        now: now,
      );

      expect(outcome.adaptiveFollowUp, isNull);
    });

    test('剩余题量不足时追加到队尾', () async {
      final (sessionId, itemIds) = await insertSession(wordCount: 2);
      final items = await itemsOf(sessionId);

      final outcome = await service.processAnswer(
        answer(
          wordId: items.first.wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          userAnswer: 'wrong',
        ),
        now: now,
      );

      expect(outcome.adaptiveFollowUp, isNotNull);
      final after = await itemsOf(sessionId);
      expect(after, hasLength(3));
      final last = after.last;
      expect(last.wordId, items.first.wordId);
      expect(last.taskType, StudyTaskType.wrong);
    });

    test('追问的题型比原题更需要主动产出', () async {
      // 库里题目的题型必须与提交的一致，否则认领会被判为题型不匹配。
      final (sessionId, itemIds) = await insertSession(
        wordCount: 12,
        questionType: QuestionType.enToZhChoice,
      );
      final items = await itemsOf(sessionId);

      final outcome = await service.processAnswer(
        answer(
          wordId: items.first.wordId,
          sessionId: sessionId,
          itemId: itemIds.first,
          questionType: QuestionType.enToZhChoice,
          userAnswer: 'wrong',
        ),
        now: now,
      );

      expect(
        outcome.adaptiveFollowUp!.questionType,
        QuestionType.zhToEnSpelling,
      );
    });
  });

  group('批量作答', () {
    test('整批共用一个事务', () async {
      final first = await insertWord();
      final second = await insertWord(term: 'banana');

      final outcomes = await service.processAnswers(<AnswerInput>[
        answer(wordId: first, clientAnswerId: 'a'),
        answer(wordId: second, clientAnswerId: 'b', userAnswer: 'banana'),
      ], now: now);

      expect(outcomes, hasLength(2));
      expect(await db.select(db.reviewLogs).get(), hasLength(2));
    });

    test('批次中任一题失败则整批回滚', () async {
      final good = await insertWord();
      final suspended = await insertWord(term: 'banana', isSuspended: true);

      await expectLater(
        service.processAnswers(<AnswerInput>[
          answer(wordId: good, clientAnswerId: 'a'),
          answer(wordId: suspended, clientAnswerId: 'b', userAnswer: 'banana'),
        ], now: now),
        throwsA(isA<AppError>()),
      );

      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect(await db.select(db.reviewCards).get(), isEmpty);
    });
  });

  group('间隔预览', () {
    test('新词返回四个等级且顺序固定', () async {
      final wordId = await insertWord();
      final previews = await service.previewIntervals(wordId, now: now);

      expect(previews.map((item) => item.rating).toList(), <ReviewRating>[
        ReviewRating.again,
        ReviewRating.hard,
        ReviewRating.good,
        ReviewRating.easy,
      ]);
      for (var index = 1; index < previews.length; index += 1) {
        expect(
          previews[index].nextDueAt,
          greaterThanOrEqualTo(previews[index - 1].nextDueAt),
        );
      }
    });

    test('预览不写库', () async {
      final wordId = await insertWord();
      await service.previewIntervals(wordId, now: now);
      expect(await db.select(db.reviewCards).get(), isEmpty);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    });
  });

  group('统计与错词累积', () {
    test('多次作答后统计累加且正确率正确', () async {
      final wordId = await insertWord();

      await service.processAnswer(
        answer(wordId: wordId, clientAnswerId: 'a'),
        now: now,
      );
      await service.processAnswer(
        answer(wordId: wordId, clientAnswerId: 'b', userAnswer: 'wrong'),
        now: now + minuteMs,
      );

      final stats = await db.select(db.wordReviewStats).getSingle();
      expect(stats.totalReviews, 2);
      expect(stats.correctReviews, 1);
      expect(stats.recentWrong14d, 1);
      expect(stats.recentAgain30d, 1);
    });

    test('连续答对累积错词的连对天数', () async {
      final wordId = await insertWord();
      // 先答错建立错词行。
      await service.processAnswer(
        answer(wordId: wordId, clientAnswerId: 'w', userAnswer: 'wrong'),
        now: now,
      );
      // 隔一天答对。
      await service.processAnswer(answer(wordId: wordId), now: now + dayMs);

      final wrong = await db.select(db.wrongWordStates).getSingle();
      expect(wrong.consecutiveCorrect, 1);
      expect(wrong.active, isTrue, reason: '还需连对 3 天且距答错 2 天');
    });

    test('答错后熟练度低于一直答对', () async {
      final goodWord = await insertWord();
      final badWord = await insertWord(term: 'banana');

      final good = await service.processAnswer(
        answer(wordId: goodWord, clientAnswerId: 'g'),
        now: now,
      );
      final bad = await service.processAnswer(
        answer(wordId: badWord, clientAnswerId: 'b', userAnswer: 'wrong'),
        now: now,
      );

      expect(bad.masteryScore, lessThan(good.masteryScore));
    });
  });
}
