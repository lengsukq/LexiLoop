/// 游戏 DAO 的测试：高分榜、候选查询、会话收尾。
///
/// 这一层最容易出错且最难定位的是**候选查询的准入条件**：释义为空的词条
/// 一旦混进候选，游戏里就会出现一道没有题干的题；而释义重复的两个词条
/// 会让选择题出现两个一模一样的选项（正确答案看起来有两个）。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';

void main() {
  late AppDatabase db;
  late GameDao dao;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = GameDao(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertWord({
    required String term,
    String definitionsJson = '[{"language":"zh","text":"释义"}]',
    String pronunciationsJson = '[]',
    LexicalContentType contentType = LexicalContentType.word,
    InitializationStatus status = InitializationStatus.ready,
    bool suspended = false,
    int masteryScore = 0,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: contentType == LexicalContentType.sentence
                ? EntryType.phrase
                : EntryType.word,
            contentType: Value<LexicalContentType>(contentType),
            initializationStatus: Value<InitializationStatus>(status),
            isSuspended: Value<bool>(suspended),
            masteryScore: Value<int>(masteryScore),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: Value<String>(definitionsJson),
            pronunciationsJson: Value<String>(pronunciationsJson),
            updatedAt: now,
          ),
        );
    return id;
  }

  group('高分榜', () {
    test('bestScore 取最大值，没有记录时为 0', () async {
      expect(await dao.bestScore(GameMode.whackAMole), 0);
      await dao.saveHighScore(
        mode: GameMode.whackAMole,
        score: 120,
        maxCombo: 3,
        accuracy: 60,
        elapsedMs: 1000,
        now: now,
      );
      await dao.saveHighScore(
        mode: GameMode.whackAMole,
        score: 480,
        maxCombo: 8,
        accuracy: 90,
        elapsedMs: 2000,
        now: now + 1,
      );
      expect(await dao.bestScore(GameMode.whackAMole), 480);
      expect(await dao.bestScore(GameMode.wordStack), 0, reason: '模式之间互不影响');
    });

    test('topScores 按分数降序，同分按时间早的在前', () async {
      await dao.saveHighScore(
        mode: GameMode.wordStack,
        score: 300,
        maxCombo: 2,
        accuracy: 50,
        elapsedMs: 10,
        now: now + 3,
      );
      await dao.saveHighScore(
        mode: GameMode.wordStack,
        score: 300,
        maxCombo: 4,
        accuracy: 50,
        elapsedMs: 10,
        now: now + 1,
      );
      await dao.saveHighScore(
        mode: GameMode.wordStack,
        score: 500,
        maxCombo: 5,
        accuracy: 80,
        elapsedMs: 10,
        now: now + 2,
      );
      final top = await dao.topScores(mode: GameMode.wordStack, limit: 10);
      expect(top.map((item) => item.score).toList(), <int>[500, 300, 300]);
      expect(top[1].playedAt, now + 1, reason: '同分时时间早的排前面');
      expect(top[2].playedAt, now + 3);
      expect(top.first.detail.maxCombo, 5);
    });

    test('topScores 遵守 limit', () async {
      for (var index = 0; index < 5; index += 1) {
        await dao.saveHighScore(
          mode: GameMode.match,
          score: index * 10,
          maxCombo: 0,
          accuracy: 0,
          elapsedMs: 0,
          now: now + index,
        );
      }
      expect((await dao.topScores(mode: GameMode.match, limit: 2)).length, 2);
    });

    test('recentScores 跨模式按时间倒序', () async {
      await dao.saveHighScore(
        mode: GameMode.match,
        score: 10,
        maxCombo: 0,
        accuracy: 0,
        elapsedMs: 0,
        now: now,
      );
      await dao.saveHighScore(
        mode: GameMode.phonetics,
        score: 20,
        maxCombo: 0,
        accuracy: 0,
        elapsedMs: 0,
        now: now + 10,
      );
      final recent = await dao.recentScores(limit: 5);
      expect(recent.map((item) => item.mode).toList(), <GameMode>[
        GameMode.phonetics,
        GameMode.match,
      ]);
    });

    test('rankOf 返回更高分记录数 + 1', () async {
      await dao.saveHighScore(
        mode: GameMode.match,
        score: 100,
        maxCombo: 0,
        accuracy: 0,
        elapsedMs: 0,
        now: now,
      );
      await dao.saveHighScore(
        mode: GameMode.match,
        score: 200,
        maxCombo: 0,
        accuracy: 0,
        elapsedMs: 0,
        now: now + 1,
      );
      expect(await dao.rankOf(mode: GameMode.match, score: 300), 1);
      expect(await dao.rankOf(mode: GameMode.match, score: 150), 2);
      expect(await dao.rankOf(mode: GameMode.match, score: 50), 3);
    });
  });

  group('候选查询', () {
    test('释义为空的词条不会进入候选', () async {
      await insertWord(term: 'empty', definitionsJson: '[]');
      await insertWord(
        term: 'blank',
        definitionsJson: '[{"language":"zh","text":" "}]',
      );
      await insertWord(term: 'broken', definitionsJson: '不是 JSON');
      await insertWord(
        term: 'ok',
        definitionsJson: '[{"language":"zh","text":"好"}]',
      );
      final candidates = await dao.loadCandidates(now: now, limit: 10);
      expect(candidates.map((item) => item.term).toList(), <String>['ok']);
    });

    test('释义重复的词条只保留一条', () async {
      await insertWord(
        term: 'a',
        definitionsJson: '[{"language":"zh","text":"相同"}]',
      );
      await insertWord(
        term: 'b',
        definitionsJson: '[{"language":"zh","text":"相同"}]',
      );
      final candidates = await dao.loadCandidates(now: now, limit: 10);
      expect(candidates.length, 1);
    });

    test('未就绪与已暂停的词条被排除', () async {
      await insertWord(term: 'pending', status: InitializationStatus.pending);
      await insertWord(term: 'suspended', suspended: true);
      await insertWord(term: 'ready');
      final candidates = await dao.loadCandidates(now: now, limit: 10);
      expect(candidates.map((item) => item.term).toList(), <String>['ready']);
    });

    test('wordsOnly 只保留纯字母单词', () async {
      await insertWord(term: 'hello');
      await insertWord(term: 'take off');
      await insertWord(
        term: 'a',
        definitionsJson: '[{"language":"zh","text":"甲"}]',
      );
      await insertWord(
        term: 'sentence here',
        contentType: LexicalContentType.sentence,
        definitionsJson: '[{"language":"zh","text":"句子"}]',
      );
      final candidates = await dao.loadCandidates(
        now: now,
        limit: 10,
        wordsOnly: true,
      );
      expect(candidates.map((item) => item.term).toList(), <String>['hello']);
    });

    test('优先级：错词 > 近期失误 > 到期 > 普通', () async {
      final wrongId = await insertWord(
        term: 'wrong',
        definitionsJson: '[{"language":"zh","text":"错词"}]',
      );
      final recentId = await insertWord(
        term: 'recent',
        definitionsJson: '[{"language":"zh","text":"近期"}]',
      );
      final dueId = await insertWord(
        term: 'due',
        definitionsJson: '[{"language":"zh","text":"到期"}]',
      );
      await insertWord(
        term: 'normal',
        definitionsJson: '[{"language":"zh","text":"普通"}]',
      );

      await db
          .into(db.wrongWordStates)
          .insert(
            WrongWordStatesCompanion.insert(
              wordId: Value<int>(wrongId),
              active: Value<bool>(true),
              updatedAt: now,
            ),
          );
      await db
          .into(db.wordReviewStats)
          .insert(
            WordReviewStatsCompanion.insert(
              wordId: Value<int>(recentId),
              recentAgain14d: Value<int>(2),
              updatedAt: Value<int>(now),
            ),
          );
      await db
          .into(db.reviewCards)
          .insert(
            ReviewCardsCompanion.insert(
              wordId: Value<int>(dueId),
              dueAt: now - 1000,
              stability: 1,
              difficulty: 1,
              elapsedDays: 0,
              scheduledDays: 1,
              reps: 1,
              lapses: 0,
              fsrsState: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final candidates = await dao.loadCandidates(now: now, limit: 10);
      expect(candidates.map((item) => item.priority).toList(), <GamePriority>[
        GamePriority.wrong,
        GamePriority.recentMistake,
        GamePriority.due,
        GamePriority.normal,
      ]);
    });

    test('尚未到期的卡片不算到期', () async {
      final id = await insertWord(term: 'future');
      await db
          .into(db.reviewCards)
          .insert(
            ReviewCardsCompanion.insert(
              wordId: Value<int>(id),
              dueAt: now + 100000,
              stability: 1,
              difficulty: 1,
              elapsedDays: 0,
              scheduledDays: 1,
              reps: 1,
              lapses: 0,
              fsrsState: 1,
              createdAt: now,
              updatedAt: now,
            ),
          );
      final candidates = await dao.loadCandidates(now: now, limit: 10);
      expect(candidates.single.priority, GamePriority.normal);
    });

    test('excludeWordsInActiveSessions 排除正在别的会话里等作答的词条', () async {
      final busyId = await insertWord(
        term: 'busy',
        definitionsJson: '[{"language":"zh","text":"忙"}]',
      );
      await insertWord(
        term: 'free',
        definitionsJson: '[{"language":"zh","text":"闲"}]',
      );
      final sessionId = await db
          .into(db.studySessions)
          .insert(
            StudySessionsCompanion.insert(
              sessionType: StudyMode.daily,
              startedAt: now,
              createdAt: now,
            ),
          );
      await db
          .into(db.studySessionItems)
          .insert(
            StudySessionItemsCompanion.insert(
              studySessionId: sessionId,
              position: 0,
              wordId: busyId,
              taskType: StudyTaskType.review,
              questionType: QuestionType.enToZhChoice,
              createdAt: now,
            ),
          );

      final withExclusion = await dao.loadCandidates(
        now: now,
        limit: 10,
        excludeWordsInActiveSessions: true,
      );
      expect(withExclusion.map((item) => item.term).toList(), <String>['free']);
      final without = await dao.loadCandidates(now: now, limit: 10);
      expect(without.length, 2);
    });

    test('读音 JSON 原样带出，供音标训练解析', () async {
      await insertWord(
        term: 'sheep',
        definitionsJson: '[{"language":"zh","text":"绵羊"}]',
        pronunciationsJson: '[{"accent":"US","phonetic":"ʃiːp"}]',
      );
      final candidates = await dao.loadCandidates(now: now, limit: 10);
      expect(candidates.single.pronunciationsJson, contains('ʃiːp'));
    });
  });

  group('会话读写', () {
    Future<int> insertSession({
      String? sourceType,
      int itemCount = 2,
      StudyMode mode = StudyMode.daily,
      String prefix = 'w',
    }) async {
      final sessionId = await db
          .into(db.studySessions)
          .insert(
            StudySessionsCompanion.insert(
              sessionType: mode,
              sourceType: Value<String?>(sourceType),
              startedAt: now - 5000,
              plannedCount: Value<int>(itemCount),
              createdAt: now - 5000,
            ),
          );
      for (var index = 0; index < itemCount; index += 1) {
        final wordId = await insertWord(
          term: '$prefix$index',
          definitionsJson: '[{"language":"zh","text":"$prefix 释义$index"}]',
        );
        await db
            .into(db.studySessionItems)
            .insert(
              StudySessionItemsCompanion.insert(
                studySessionId: sessionId,
                position: index * sessionItemPositionStep,
                wordId: wordId,
                taskType: StudyTaskType.listening,
                questionType: QuestionType.listeningSpelling,
                createdAt: now - 5000,
              ),
            );
      }
      return sessionId;
    }

    test('sessionItemIds 返回词条到题目的映射', () async {
      final sessionId = await insertSession(sourceType: 'GAME_X');
      final map = await dao.sessionItemIds(sessionId);
      expect(map.length, 2);
      expect(map.values.every((id) => id > 0), isTrue);
    });

    test('closeOpenSessions 把待答题目标记为过期并收尾会话', () async {
      final sessionId = await insertSession(sourceType: 'GAME_WHACK_A_MOLE');
      final other = await insertSession(sourceType: 'MATCH_GAME', prefix: 'm');

      final closed = await dao.closeOpenSessions(
        sourceTypePattern: 'GAME_WHACK_A_MOLE',
        now: now,
      );
      expect(closed, 1);

      final items = await (db.select(
        db.studySessionItems,
      )..where((row) => row.studySessionId.equals(sessionId))).get();
      expect(
        items.every((item) => item.status == StudyItemStatus.skipped),
        isTrue,
      );
      expect(
        items.every((item) => item.skipReason == 'SESSION_EXPIRED'),
        isTrue,
      );
      final session = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
      expect(session.completedAt, now);
      expect(session.skippedCount, 2);
      expect(session.completedCount, 2);
      expect(session.durationMs, 5000);

      final untouched = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(other))).getSingle();
      expect(untouched.completedAt, isNull);
    });

    test('completePhoneticSession 记账并跳过未作答的题目', () async {
      final sessionId = await insertSession(sourceType: 'PHONETIC_TRAINING');
      final map = await dao.sessionItemIds(sessionId);
      final ids = map.values.toList()..sort();
      await dao.completePhoneticSession(
        sessionId: sessionId,
        answers: <GameAnswerRecord>[
          GameAnswerRecord(
            itemId: ids[0],
            wordId: map.keys.first,
            solved: true,
            hadMistake: false,
            durationMs: 1200,
          ),
          GameAnswerRecord(
            itemId: ids[1],
            wordId: map.keys.last,
            solved: false,
            hadMistake: true,
            durationMs: 800,
          ),
        ],
        answeredItemIds: <int>{ids[0]},
        elapsedMs: 2000,
        now: now,
      );

      final session = await (db.select(
        db.studySessions,
      )..where((row) => row.id.equals(sessionId))).getSingle();
      expect(session.completedAt, now);
      expect(session.correctCount, 1);
      expect(session.wrongCount, 0);
      expect(session.skippedCount, 1);
      expect(session.completedCount, 1);
      expect(session.durationMs, 2000);

      final answered = await (db.select(
        db.studySessionItems,
      )..where((row) => row.id.equals(ids[0]))).getSingle();
      expect(answered.status, StudyItemStatus.answered);
      expect(answered.skipReason, isNull);
      final skipped = await (db.select(
        db.studySessionItems,
      )..where((row) => row.id.equals(ids[1]))).getSingle();
      expect(skipped.status, StudyItemStatus.skipped);
      expect(skipped.skipReason, 'SESSION_EXPIRED');
    });
  });
}
