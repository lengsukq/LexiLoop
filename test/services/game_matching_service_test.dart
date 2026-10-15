/// 配对编排的集成测试。
///
/// 对应旧版 `modules/matching/service.ts`：至少 4 个带释义且释义不重复的
/// 可学习词条，否则抛 `notEnoughMatchingWords`；配对结果通过
/// `ReviewService.processAnswers` 落库（`questionType` 为 `EN_TO_ZH_CHOICE`，
/// 期望答案是中文释义）。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/matching.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/services/matching_service.dart';
import 'package:lexiloop/services/review_service.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../domain/games/random_source.dart';

void main() {
  late AppDatabase db;
  late MatchingService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = MatchingService(
      StudyDao(db),
      ReviewService(db, SettingsService(SettingsDao(db))),
      GameDao(db),
    );
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertWords(int count) async {
    for (var index = 0; index < count; index += 1) {
      final suffix = String.fromCharCode(97 + index);
      final id = await db
          .into(db.words)
          .insert(
            WordsCompanion.insert(
              term: 'term$suffix',
              normalizedTerm: 'term$suffix',
              sourceLanguage: 'en',
              targetLanguage: 'zh',
              entryType: EntryType.word,
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
            WordContentsCompanion.insert(
              wordId: Value<int>(id),
              definitionsJson: Value<String>(
                '[{"language":"zh","text":"释义$suffix"}]',
              ),
              updatedAt: now,
            ),
          );
    }
  }

  test('不足 4 个词条时抛 notEnoughMatchingWords', () async {
    await insertWords(3);
    await expectLater(
      service.start(pairCount: 4, durationSeconds: 60, now: now),
      throwsA(
        isA<ConflictError>().having(
          (error) => error.code,
          'code',
          AppErrorCode.notEnoughMatchingWords,
        ),
      ),
    );
  });

  test('对数与时限被夹到旧版边界内', () async {
    await insertWords(10);
    final small = await service.start(
      pairCount: 1,
      durationSeconds: 5,
      now: now,
      random: constantRandom(),
    );
    expect(small.questions.length, matchingMinimumPairCount);
    expect(small.plan.durationMs, matchingMinimumDurationSeconds * 1000);
    expect(small.plan.itemCount, matchingMinimumPairCount);

    final big = await service.start(
      pairCount: 99,
      durationSeconds: 999,
      now: now + 1000,
      random: constantRandom(),
    );
    expect(big.questions.length, matchingMaximumPairCount);
    expect(big.plan.durationMs, matchingMaximumDurationSeconds * 1000);
  });

  test('会话来源与会话题型与旧版一致', () async {
    await insertWords(6);
    final session = await service.start(
      pairCount: 5,
      durationSeconds: 60,
      now: now,
      random: constantRandom(),
    );
    final row = await (db.select(
      db.studySessions,
    )..where((item) => item.id.equals(session.sessionId))).getSingle();
    expect(row.sourceType, 'MATCH_GAME');
    expect(row.sessionType, StudyMode.wrongWords);
    final items = await (db.select(
      db.studySessionItems,
    )..where((item) => item.studySessionId.equals(session.sessionId))).get();
    expect(items.length, 5);
    expect(
      items.every((item) => item.questionType == QuestionType.enToZhChoice),
      isTrue,
    );
    expect(
      items.every((item) => item.taskType == StudyTaskType.newWord),
      isTrue,
    );
  });

  test('全部配对成功时写复习日志并结束会话', () async {
    await insertWords(4);
    final session = await service.start(
      pairCount: 4,
      durationSeconds: 60,
      now: now,
      random: constantRandom(),
    );
    var board = startMatchingBoard(
      plan: session.plan,
      pairs: session.questions,
      random: constantRandom(),
    );
    board = matchBoardNext(board, const StartMatch());
    for (final question in session.questions) {
      // 每对之间推进 1 秒：配对的逐题耗时是「距上次配对的时间」。
      board = matchBoardNext(board, const TickMatch(1000));
      board = matchBoardNext(
        board,
        TapMatchCard(side: MatchSide.word, itemId: question.itemId),
      );
      board = matchBoardNext(
        board,
        TapMatchCard(side: MatchSide.definition, itemId: question.itemId),
      );
    }
    expect(board.isComplete, isTrue);

    final result = await service.complete(
      session: session,
      state: board,
      now: now + 30000,
    );
    expect(result.summary.firstTryCorrect, 4);
    expect(result.summary.accuracy, 100);
    expect(result.score, greaterThan(0));

    final logs = await db
        .customSelect(
          'SELECT client_answer_id, rating, question_type, user_answer, '
          'duration_ms FROM review_logs',
        )
        .get();
    expect(logs.length, 4);
    expect(
      logs.map((row) => row.read<String>('client_answer_id')).toSet().length,
      4,
    );
    expect(
      logs.every(
        (row) => row.read<String>('question_type') == 'EN_TO_ZH_CHOICE',
      ),
      isTrue,
    );
    expect(logs.every((row) => row.read<String>('rating') == 'GOOD'), isTrue);
    // 期望答案是中文释义而不是英文词条。
    expect(logs.map((row) => row.read<String>('user_answer')).toSet(), <String>{
      '释义a',
      '释义b',
      '释义c',
      '释义d',
    });
    expect(
      logs.every((row) => row.read<int>('duration_ms') > 0),
      isTrue,
      reason: '配对没有逐题计时，用平均耗时兜底',
    );

    final sessionRow = await (db.select(
      db.studySessions,
    )..where((row) => row.id.equals(session.sessionId))).getSingle();
    expect(sessionRow.completedAt, isNotNull);
    expect(sessionRow.correctCount, 4);
    expect(sessionRow.durationMs, greaterThan(0));

    final scores = await (db.select(db.gameHighScores)).get();
    expect(scores.single.gameMode, 'MATCH');
    expect(scores.single.score, result.score);
  });

  test('未配对完成的题目按「忘记」提交', () async {
    await insertWords(4);
    final session = await service.start(
      pairCount: 4,
      durationSeconds: 60,
      now: now,
      random: constantRandom(),
    );
    var board = matchBoardNext(
      startMatchingBoard(
        plan: session.plan,
        pairs: session.questions,
        random: constantRandom(),
      ),
      const StartMatch(),
    );
    // 只配一对，其余靠时间耗尽。
    final first = session.questions.first;
    board = matchBoardNext(
      board,
      TapMatchCard(side: MatchSide.word, itemId: first.itemId),
    );
    board = matchBoardNext(
      board,
      TapMatchCard(side: MatchSide.definition, itemId: first.itemId),
    );
    board = matchBoardNext(board, const TickMatch(60000));
    expect(board.core.isFinished, isTrue);

    final result = await service.complete(
      session: session,
      state: board,
      now: now + 60000,
    );
    expect(result.summary.firstTryCorrect, 1);
    expect(result.summary.missed, 3);
    final logs = await db
        .customSelect('SELECT rating, user_answer FROM review_logs')
        .get();
    expect(logs.length, 4);
    expect(
      logs.where((row) => row.read<String>('rating') == 'AGAIN').length,
      3,
    );
    expect(
      logs
          .where((row) => row.read<String>('user_answer') == matchMistakeAnswer)
          .length,
      3,
    );
  });

  test('高分榜按 MATCH 模式记录且模式间互不影响', () async {
    await insertWords(4);
    final session = await service.start(
      pairCount: 4,
      durationSeconds: 60,
      now: now,
      random: constantRandom(),
    );
    final board = matchBoardNext(
      startMatchingBoard(
        plan: session.plan,
        pairs: session.questions,
        random: constantRandom(),
      ),
      const StartMatch(),
    );
    await service.complete(session: session, state: board, now: now + 1000);
    expect(await GameDao(db).bestScore(GameMode.match), greaterThan(0));
    expect(await GameDao(db).bestScore(GameMode.whackAMole), 0);
  });
}
