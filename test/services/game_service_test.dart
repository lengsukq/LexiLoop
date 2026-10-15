/// 小游戏编排的集成测试。
///
/// 最关键的一条是**结算走 `ReviewService.processAnswers` 时传入的
/// `AnswerInput` 数量与作答数一致、且 `clientAnswerId` 互不相同**：
/// 幂等键重复会让第二次作答被静默吞掉（`ReviewService` 按
/// `client_answer_id` 判重），这类 bug 在界面上表现为「分数对了但复习
/// 进度没动」，极难定位。
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
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_runtime.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/domain/games/whack_a_mole.dart';
import 'package:lexiloop/domain/games/word_stack.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/services/review_service.dart';
import 'package:lexiloop/services/settings_service.dart';

import '../domain/games/random_source.dart';

void main() {
  late AppDatabase db;
  late GameService service;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = GameService(
      StudyDao(db),
      ReviewService(db, SettingsService(SettingsDao(db))),
      GameDao(db),
    );
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord(String term, String meaning) async {
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
              '[{"language":"zh","text":"$meaning"}]',
            ),
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 插入 [count] 个词条。
  ///
  /// 词条名必须是纯字母：单词拼图题的候选过滤用
  /// `letterBankTermPattern`（3–14 个字母），带数字的词条会被挡掉。
  Future<void> insertWords(int count, {String prefix = 'word'}) async {
    for (var index = 0; index < count; index += 1) {
      final suffix = String.fromCharCode(97 + index);
      await insertWord('$prefix$suffix', '$prefix 释义$suffix');
    }
  }

  Future<List<QueryRow>> reviewLogs() => db
      .customSelect(
        'SELECT client_answer_id, word_id, rating, question_type, user_answer, '
        'study_session_id, study_session_item_id FROM review_logs',
      )
      .get();

  group('开局', () {
    test('候选不足 4 个时抛 notEnoughGameWords', () async {
      await insertWords(3);
      await expectLater(
        service.start(mode: GameMode.whackAMole, now: now),
        throwsA(
          isA<ConflictError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.notEnoughGameWords,
          ),
        ),
      );
    });

    test('开局创建会话、造题并回填题目 ID', () async {
      await insertWords(6);
      final session = await service.start(
        mode: GameMode.whackAMole,
        now: now,
        random: constantRandom(),
      );
      expect(session.mode, GameMode.whackAMole);
      expect(session.questions.length, 6);
      expect(session.plan.itemCount, 6);
      expect(session.plan.durationMs, whackAMoleDurationSeconds * 1000);
      for (final question in session.questions) {
        expect(question.itemId, greaterThan(0));
        expect(question.choices.options.length, gameChoiceCount);
        expect(question.choices.options, contains(question.word.term));
      }
      final sessionRow = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(session.sessionId))).getSingle();
      expect(sessionRow.sessionType, StudyMode.daily);
      expect(sessionRow.sourceType, 'GAME_WHACK_A_MOLE');
      expect(sessionRow.plannedCount, 6);
    });

    test('单词拼图只取纯字母单词并带字母块', () async {
      await insertWords(5);
      await insertWord('take off', '起飞');
      await insertWord('a', '一个');
      final session = await service.start(
        mode: GameMode.wordBuilder,
        now: now,
        random: constantRandom(),
      );
      expect(
        session.questions.every((item) => item.word.letters.isNotEmpty),
        isTrue,
      );
      expect(
        session.questions.every((item) => item.choices.options.isEmpty),
        isTrue,
      );
      final sessionRow = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(session.sessionId))).getSingle();
      expect(sessionRow.sessionType, StudyMode.spelling);
    });

    test('开局前会收尾同来源的未完成会话', () async {
      await insertWords(5);
      final first = await service.start(
        mode: GameMode.wordStack,
        now: now,
        random: constantRandom(),
      );
      final second = await service.start(
        mode: GameMode.wordStack,
        now: now + 1000,
        random: constantRandom(),
      );
      final old = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(first.sessionId))).getSingle();
      expect(old.completedAt, isNotNull);
      final fresh = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(second.sessionId))).getSingle();
      expect(fresh.completedAt, isNull);
    });
  });

  group('结算', () {
    Future<GameSession> startAndPlay() async {
      await insertWords(5);
      final session = await service.start(
        mode: GameMode.whackAMole,
        now: now,
        random: constantRandom(),
      );
      return session;
    }

    test('逐题提交：数量与作答数一致，幂等键互不相同', () async {
      final session = await startAndPlay();
      final runtime = startGameRuntime(
        mode: session.mode,
        plan: session.plan,
        questions: session.questions,
        random: constantRandom(),
      );
      // 第 1 题答对，第 2 题先错后对，其余未作答。
      var mole = runtime as WhackAMoleRuntime;
      mole =
          mole.dispatch(WhackMole(session.questions[0].word.term))!
              as WhackAMoleRuntime;
      mole = mole.dispatch(const AdvanceWhackAMole())! as WhackAMoleRuntime;
      mole = mole.dispatch(const WhackMole('不存在的词'))! as WhackAMoleRuntime;
      mole =
          mole.dispatch(WhackMole(session.questions[1].word.term))!
              as WhackAMoleRuntime;
      final core = mole.core;

      final answers = core.answerRecords(session.questions);
      final result = await service.complete(
        session: session,
        summary: core.summary,
        answers: answers,
        now: now + 5000,
      );

      final logs = await reviewLogs();
      expect(logs.length, answers.length);
      final keys = logs
          .map((row) => row.read<String>('client_answer_id'))
          .toSet();
      expect(keys.length, logs.length, reason: '幂等键必须互不相同');
      expect(
        logs.every(
          (row) => row.read<int>('study_session_id') == session.sessionId,
        ),
        isTrue,
      );
      expect(
        logs.every(
          (row) => row.read<String>('question_type') == 'ZH_TO_EN_CHOICE',
        ),
        isTrue,
      );
      // 第 1 题一次答对写 GOOD 且 user_answer 是词条本身。
      final first = logs.firstWhere(
        (row) =>
            row.read<int>('study_session_item_id') ==
            session.questions[0].itemId,
      );
      expect(first.read<String>('rating'), 'GOOD');
      expect(first.read<String>('user_answer'), session.questions[0].word.term);
      // 未作答的题目按 AGAIN + 失败标记提交。
      final missed = logs.firstWhere(
        (row) =>
            row.read<int>('study_session_item_id') ==
            session.questions[4].itemId,
      );
      expect(missed.read<String>('rating'), 'AGAIN');
      expect(missed.read<String>('user_answer'), gameMistakeAnswer);

      expect(result.mode, GameMode.whackAMole);
      expect(result.score, greaterThan(0));
      expect(result.summary.total, session.questions.length);
      expect(result.leaderboard.rank, 1);
      expect(result.leaderboard.isNewBest, isTrue);
      expect(result.leaderboard.best, result.score);
      expect(result.leaderboard.top.length, 1);
    });

    test('重复结算命中幂等键，不产生新日志', () async {
      final session = await startAndPlay();
      final runtime = startGameRuntime(
        mode: session.mode,
        plan: session.plan,
        questions: session.questions,
        random: constantRandom(),
      );
      final core = runtime.core;
      final answers = core.answerRecords(session.questions);
      await service.complete(
        session: session,
        summary: core.summary,
        answers: answers,
        now: now + 5000,
      );
      final before = (await reviewLogs()).length;
      await service.complete(
        session: session,
        summary: core.summary,
        answers: answers,
        now: now + 6000,
      );
      expect((await reviewLogs()).length, before);
    });

    test('结算写入高分榜并结束会话', () async {
      final session = await startAndPlay();
      final core = startGameRuntime(
        mode: session.mode,
        plan: session.plan,
        questions: session.questions,
        random: constantRandom(),
      ).core;
      final result = await service.complete(
        session: session,
        summary: core.summary,
        answers: core.answerRecords(session.questions),
        now: now + 5000,
      );
      final scores = await (db.select(db.gameHighScores)).get();
      expect(scores.length, 1);
      expect(scores.single.gameMode, 'WHACK_A_MOLE');
      expect(scores.single.score, result.score);
      final sessionRow = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(session.sessionId))).getSingle();
      expect(sessionRow.completedAt, isNotNull);
      expect(sessionRow.completedCount, session.questions.length);
    });

    test('全部答对时评级与得分都达到该模式的较高档', () async {
      await insertWords(5);
      final session = await service.start(
        mode: GameMode.wordStack,
        now: now,
        random: constantRandom(),
      );
      var runtime = startGameRuntime(
        mode: session.mode,
        plan: session.plan,
        questions: session.questions,
        random: constantRandom(),
      );
      for (final question in session.questions) {
        runtime =
            runtime.dispatch(TapStackBlock(question.word.term)) ?? runtime;
        runtime = runtime.dispatch(const AdvanceWordStack()) ?? runtime;
      }
      final result = await service.complete(
        session: session,
        summary: runtime.core.summary,
        answers: runtime.core.answerRecords(session.questions),
        now: now + 5000,
      );
      expect(result.summary.firstTryCorrect, session.questions.length);
      expect(result.summary.accuracy, 100);
      expect(result.rank, isNot(GameRank.c));
    });
  });
}
