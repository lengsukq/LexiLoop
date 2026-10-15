/// 学习会话 DAO 的单元测试。
///
/// 这一层承载三件容易出错、出错后又很难定位的事：
/// 1. **候选池的准入条件**——释义为空、未就绪、已暂停、正在别的会话里
///    等着作答的词条都必须被挡住，否则用户会拿到一道没有选项的题；
/// 2. **会话题目的位置与状态机**——位置必须是递增的浮点（插题要取中点），
///    `resumeIndex` 必须指向第一道待答题；
/// 3. **PostgreSQL → SQLite 的 JSON 方言转换**——`json_valid` / `json_type`
///    / `json_each` 写错不会报错，只会静默过滤掉所有词条。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/distractors.dart';

void main() {
  late AppDatabase db;
  late StudyDao dao;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = StudyDao(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 建一条词条（默认 READY + 一条中文释义 + 一行 `word_contents`），
  /// 返回其 id。
  Future<int> insertWord({
    required String term,
    LexicalContentType contentType = LexicalContentType.word,
    String definitionsJson = '[{"language":"zh","text":"苹果"}]',
    String? summaryJson,
    String examplesJson = '[]',
    String confusedWordsJson = '[]',
    InitializationStatus status = InitializationStatus.ready,
    bool isSuspended = false,
    int? sourceCreatedAt,
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
            isSuspended: Value<bool>(isSuspended),
            sourceCreatedAt: Value<int?>(sourceCreatedAt),
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
            examplesJson: Value<String>(examplesJson),
            confusedWordsJson: Value<String>(confusedWordsJson),
            summaryJson: Value<String>(summaryJson ?? '{"translation":null}'),
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 给词条挂一张到期卡片。
  Future<void> insertCard(
    int wordId, {
    required int dueAt,
    double difficulty = 5,
  }) => db
      .into(db.reviewCards)
      .insert(
        ReviewCardsCompanion.insert(
          wordId: Value<int>(wordId),
          dueAt: dueAt,
          stability: 1,
          difficulty: difficulty,
          elapsedDays: 0,
          scheduledDays: 1,
          reps: 1,
          lapses: 0,
          fsrsState: 1,
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// 给词条挂一条错词状态。
  Future<void> insertWrongState(
    int wordId, {
    bool active = true,
    int wrongCount = 1,
  }) => db
      .into(db.wrongWordStates)
      .insert(
        WrongWordStatesCompanion.insert(
          wordId: Value<int>(wordId),
          active: Value<bool>(active),
          wrongCount: Value<int>(wrongCount),
          updatedAt: now,
        ),
      );

  /// 直接插入一个会话行，返回其 id（绕过 [StudyDao.createSession]，
  /// 便于构造「已完成」「已超时」这类边界会话）。
  Future<int> insertSession({
    StudyMode mode = StudyMode.daily,
    String? sourceType,
    int? startedAt,
    int? completedAt,
  }) => db
      .into(db.studySessions)
      .insert(
        StudySessionsCompanion.insert(
          sessionType: mode,
          sourceType: Value<String?>(sourceType),
          startedAt: startedAt ?? now,
          completedAt: Value<int?>(completedAt),
          createdAt: now,
        ),
      );

  /// 直接插入一道题目，返回其 id。
  Future<int> insertItem(
    int sessionId,
    int wordId, {
    double position = 0,
    StudyItemStatus status = StudyItemStatus.pending,
    StudyTaskType taskType = StudyTaskType.review,
    QuestionType questionType = QuestionType.enToZh,
    int? answeredAt,
    String? skipReason,
  }) => db
      .into(db.studySessionItems)
      .insert(
        StudySessionItemsCompanion.insert(
          studySessionId: sessionId,
          position: position,
          wordId: wordId,
          taskType: taskType,
          questionType: questionType,
          status: Value<StudyItemStatus>(status),
          answeredAt: Value<int?>(answeredAt),
          skipReason: Value<String?>(skipReason),
          createdAt: now,
        ),
      );

  /// 组装一条题目草稿。
  StudySessionItemDraft draft(
    int wordId, {
    StudyTaskType taskType = StudyTaskType.review,
    QuestionType questionType = QuestionType.enToZh,
  }) => StudySessionItemDraft(
    wordId: wordId,
    taskType: taskType,
    questionType: questionType,
  );

  /// 三个候选池里所有候选的 id（用于「某词条不出现在任何池里」这类断言）。
  Future<List<int>> allPoolIds() async {
    final due = await dao.dueCandidates(
      limit: 50,
      now: now,
      scope: CandidateScope.lexical,
    );
    final wrong = await dao.wrongCandidates(
      limit: 50,
      now: now,
      scope: CandidateScope.lexical,
    );
    final fresh = await dao.newCandidates(
      limit: 50,
      now: now,
      scope: CandidateScope.lexical,
    );
    return <int>[
      ...due.map((item) => item.id),
      ...wrong.map((item) => item.id),
      ...fresh.map((item) => item.id),
    ];
  }

  group('候选池准入', () {
    test('新建的 READY 词条进入新词候选', () async {
      final id = await insertWord(term: 'apple');

      final candidates = await dao.newCandidates(
        limit: 10,
        now: now,
        scope: CandidateScope.lexical,
      );

      expect(candidates.map((item) => item.id), <int>[id]);
      expect(candidates.single.term, 'apple');
      expect(candidates.single.normalizedTerm, 'apple');
      expect(candidates.single.sourceLanguage, 'en');
      expect(candidates.single.targetLanguage, 'zh');
      expect(candidates.single.contentType, LexicalContentType.word);
      expect(candidates.single.masteryScore, 0);
    });

    test('到期卡片进入到期候选，未到期的不进入', () async {
      final due = await insertWord(term: 'due');
      final later = await insertWord(term: 'later');
      await insertCard(due, dueAt: now - dayMs);
      await insertCard(later, dueAt: now + dayMs);

      final candidates = await dao.dueCandidates(
        limit: 10,
        now: now,
        scope: CandidateScope.lexical,
      );

      expect(candidates.map((item) => item.id), <int>[due]);
      expect(
        await dao.newCandidates(
          limit: 10,
          now: now,
          scope: CandidateScope.lexical,
        ),
        isEmpty,
        reason: '有卡片的词条不该再算新词',
      );
    });

    test('到期卡片按紧迫度排序，逾期越久越靠前', () async {
      final mild = await insertWord(term: 'mild');
      final severe = await insertWord(term: 'severe');
      await insertCard(mild, dueAt: now - dayMs);
      await insertCard(severe, dueAt: now - 5 * dayMs);

      final candidates = await dao.dueCandidates(
        limit: 10,
        now: now,
        scope: CandidateScope.lexical,
      );

      expect(candidates.map((item) => item.id), <int>[severe, mild]);
    });

    test('活跃错词进入错词候选，已解除的不进入', () async {
      final wrong = await insertWord(term: 'wrong');
      final resolved = await insertWord(term: 'resolved');
      await insertWrongState(wrong, wrongCount: 3);
      await insertWrongState(resolved, active: false);

      final candidates = await dao.wrongCandidates(
        limit: 10,
        now: now,
        scope: CandidateScope.lexical,
      );

      expect(candidates.map((item) => item.id), <int>[wrong]);
    });

    test('释义为空的词条不进入任何候选池', () async {
      // 三种「空释义」形态：空数组、全空白文本、非法 JSON。
      // 非法 JSON 尤其重要：SQLite 的 json_type 对非法输入会**抛错**，
      // 忘了先 json_valid 会让整条候选查询失败。
      final empty = await insertWord(term: 'empty', definitionsJson: '[]');
      final blank = await insertWord(
        term: 'blank',
        definitionsJson: '[{"language":"zh","text":"   "}]',
      );
      final broken = await insertWord(
        term: 'broken',
        definitionsJson: 'not-json',
      );
      for (final id in <int>[empty, blank, broken]) {
        await insertCard(id, dueAt: now - dayMs);
        await insertWrongState(id);
      }

      expect(await allPoolIds(), isEmpty);
      final availability = await dao.countAvailable(
        now: now,
        scope: CandidateScope.lexical,
      );
      expect(availability.due, 0);
      expect(availability.wrong, 0);
      expect(availability.fresh, 0);
    });

    test('暂停或未就绪的词条不进入候选池', () async {
      final suspended = await insertWord(term: 'suspended', isSuspended: true);
      final pending = await insertWord(
        term: 'pending',
        status: InitializationStatus.pending,
      );
      final failed = await insertWord(
        term: 'failed',
        status: InitializationStatus.failed,
      );
      for (final id in <int>[suspended, pending, failed]) {
        await insertCard(id, dueAt: now - dayMs);
        await insertWrongState(id);
      }

      expect(await allPoolIds(), isEmpty);
    });

    test('PARTIAL 词条与 READY 一样可进入候选池', () async {
      final id = await insertWord(
        term: 'partial',
        status: InitializationStatus.partial,
      );

      final candidates = await dao.newCandidates(
        limit: 10,
        now: now,
        scope: CandidateScope.lexical,
      );

      expect(candidates.map((item) => item.id), <int>[id]);
    });

    test('句子只在句子范围出现，单词短语只在词汇范围出现', () async {
      // 句子只带 summary.translation、没有逐词释义——旧版允许这种形态。
      final sentence = await insertWord(
        term: 'The cat sat on the mat.',
        contentType: LexicalContentType.sentence,
        definitionsJson: '[]',
        summaryJson: '{"translation":"猫坐在垫子上。"}',
      );
      final word = await insertWord(term: 'cat');

      Future<List<int>> ids(CandidateScope scope) async {
        final candidates = await dao.newCandidates(
          limit: 10,
          now: now,
          scope: scope,
        );
        return candidates.map((item) => item.id).toList();
      }

      expect(await ids(CandidateScope.sentence), <int>[sentence]);
      expect(await ids(CandidateScope.lexical), <int>[word]);
      // ALL 的释义判定沿用旧版 `hasMeaningSql('ALL')` 的语义（只看
      // definitions），因此只带整句翻译的句子不在 ALL 里。
      expect(await ids(CandidateScope.all), <int>[word]);
    });

    test('主动跳过的词条在冷却期内不再进入候选', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(word)],
        now: now,
      );
      final item = (await dao.loadSession(sessionId)).items.single;
      await dao.skipItem(
        sessionId: sessionId,
        itemId: item.itemId,
        reason: 'LATER',
        now: now,
      );

      expect(
        await dao.newCandidates(
          limit: 10,
          now: now,
          scope: CandidateScope.lexical,
        ),
        isEmpty,
      );
      final later = now + skipCooldownMs + 1;
      final recovered = await dao.newCandidates(
        limit: 10,
        now: later,
        scope: CandidateScope.lexical,
      );
      expect(recovered.map((candidate) => candidate.id), <int>[word]);
    });

    test('leastRecentlyReviewedCandidates 排除指定词条', () async {
      final first = await insertWord(term: 'first', sourceCreatedAt: now);
      final second = await insertWord(term: 'second', sourceCreatedAt: now);
      await insertCard(first, dueAt: now + dayMs);
      await insertCard(second, dueAt: now + dayMs);

      final candidates = await dao.leastRecentlyReviewedCandidates(
        limit: 10,
        now: now,
        scope: CandidateScope.lexical,
        excludedIds: <int>{first},
      );

      expect(candidates.map((item) => item.id), <int>[second]);
    });
  });

  group('会话生命周期', () {
    test('createSession 落库后能完整读回，位置从 0 递增', () async {
      final alpha = await insertWord(term: 'alpha');
      final bravo = await insertWord(term: 'bravo');
      final charlie = await insertWord(term: 'charlie');

      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[
          draft(alpha, questionType: QuestionType.enToZhChoice),
          draft(bravo, questionType: QuestionType.zhToEnChoice),
          draft(charlie),
        ],
        now: now,
      );

      final view = await dao.loadSession(sessionId);

      expect(view.id, sessionId);
      expect(view.mode, StudyMode.daily);
      expect(view.sourceType, isNull);
      expect(view.startedAt, now);
      expect(view.completedAt, isNull);
      expect(view.plannedCount, 3);
      expect(view.completedCount, 0);
      expect(view.skippedCount, 0);
      expect(view.resumed, isFalse);
      expect(view.items, hasLength(3));
      expect(view.items.map((item) => item.position), <double>[
        0,
        sessionItemPositionStep,
        2 * sessionItemPositionStep,
      ]);
      expect(view.resumeIndex, 0);
      expect(view.isFinished, isFalse);
      expect(view.currentItem?.itemId, view.items.first.itemId);
      expect(view.items.first.word.term, 'alpha');
      expect(view.items.first.word.definitions.single.text, '苹果');
      expect(view.items.first.status, StudyItemStatus.pending);
    });

    test('createSession 的空会话直接标记完成', () async {
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: const <StudySessionItemDraft>[],
        now: now,
      );

      final view = await dao.loadSession(sessionId);

      expect(view.items, isEmpty);
      expect(view.completedAt, now);
      expect(view.isFinished, isTrue);
      expect(view.currentItem, isNull);
    });

    test('loadSession 对不存在的会话抛 sessionNotFound', () async {
      await expectLater(
        dao.loadSession(999),
        throwsA(
          isA<NotFoundError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.sessionNotFound,
          ),
        ),
      );
    });

    test('loadSession 为各题型生成选项、填空与字母块', () async {
      final target = await insertWord(
        term: 'apple',
        examplesJson: '[{"sentence":"I eat an apple.","translation":"我吃苹果。"}]',
        confusedWordsJson: '[{"word":"pear"}, "grape"]',
      );
      await insertWord(
        term: 'pear',
        definitionsJson: '[{"language":"zh","text":"梨"}]',
      );
      await insertWord(
        term: 'grape',
        definitionsJson: '[{"language":"zh","text":"葡萄"}]',
      );
      await insertWord(
        term: 'peach',
        definitionsJson: '[{"language":"zh","text":"桃子"}]',
      );

      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[
          draft(target, questionType: QuestionType.enToZhChoice),
          draft(target, questionType: QuestionType.zhToEnChoice),
          draft(target, questionType: QuestionType.clozeSentence),
          draft(target, questionType: QuestionType.letterBank),
        ],
        now: now,
      );

      final items = (await dao.loadSession(sessionId)).items;

      expect(items[0].choices, hasLength(meaningChoiceCount));
      expect(items[0].choices, contains('苹果'));
      expect(items[0].choiceDefinitions, isEmpty);

      expect(items[1].choices, hasLength(meaningChoiceCount));
      expect(items[1].choices, contains('apple'));
      expect(items[1].choiceDefinitions['apple'], '苹果');

      expect(items[2].cloze?.sentence, 'I eat an apple.');
      expect(items[2].cloze?.blankedSentence, 'I eat an $clozeBlankToken.');
      expect(items[2].cloze?.translation, '我吃苹果。');

      final tileValues = items[3].letters.map((tile) => tile.value).toList()
        ..sort();
      expect(tileValues, <String>['a', 'e', 'l', 'p', 'p']);
      expect(items[3].letters.map((tile) => tile.id).toSet(), hasLength(5));
    });

    test('skipItem 把题目置为 SKIPPED 并推进 resumeIndex', () async {
      final alpha = await insertWord(term: 'alpha');
      final bravo = await insertWord(term: 'bravo');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(alpha), draft(bravo)],
        now: now,
      );
      final first = (await dao.loadSession(sessionId)).items.first;

      final view = await dao.skipItem(
        sessionId: sessionId,
        itemId: first.itemId,
        reason: 'LATER',
        now: now,
      );

      expect(view.items.first.status, StudyItemStatus.skipped);
      expect(view.items.first.skipReason, 'LATER');
      expect(view.resumeIndex, 1);
      expect(view.isFinished, isFalse);

      final row = await db
          .customSelect(
            'SELECT skipped_count, completed_count, completed_at '
            'FROM study_sessions WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(sessionId)],
          )
          .getSingle();
      expect(row.read<int>('skipped_count'), 1);
      expect(row.read<int>('completed_count'), 1);
      expect(row.readNullable<int>('completed_at'), isNull);
    });

    test('skipItem 跳完最后一道题会收尾会话', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(word)],
        now: now,
      );
      final item = (await dao.loadSession(sessionId)).items.single;

      final view = await dao.skipItem(
        sessionId: sessionId,
        itemId: item.itemId,
        reason: 'LATER',
        now: now,
      );

      expect(view.completedAt, now);
      expect(view.durationMs, 0);
      expect(view.isFinished, isTrue);
    });

    test('skipItem 对不存在的题目抛 studyItemNotFound', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(word)],
        now: now,
      );

      await expectLater(
        dao.skipItem(
          sessionId: sessionId,
          itemId: 999,
          reason: 'LATER',
          now: now,
        ),
        throwsA(
          isA<NotFoundError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.studyItemNotFound,
          ),
        ),
      );
    });

    test('skipItem 对已处理的题目抛 studyItemAlreadyProcessed', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(word), draft(word)],
        now: now,
      );
      final item = (await dao.loadSession(sessionId)).items.first;
      await dao.skipItem(
        sessionId: sessionId,
        itemId: item.itemId,
        reason: 'LATER',
        now: now,
      );

      await expectLater(
        dao.skipItem(
          sessionId: sessionId,
          itemId: item.itemId,
          reason: 'LATER',
          now: now,
        ),
        throwsA(
          isA<ConflictError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.studyItemAlreadyProcessed,
          ),
        ),
      );
    });

    test('全部题目作答后 isFinished 为 true', () async {
      final alpha = await insertWord(term: 'alpha');
      final bravo = await insertWord(term: 'bravo');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(alpha), draft(bravo)],
        now: now,
      );
      await (db.update(
        db.studySessionItems,
      )..where((row) => row.studySessionId.equals(sessionId))).write(
        const StudySessionItemsCompanion(
          status: Value<StudyItemStatus>(StudyItemStatus.answered),
        ),
      );

      final view = await dao.loadSession(sessionId, resumed: true);

      expect(view.isFinished, isTrue);
      expect(view.resumeIndex, view.items.length);
      expect(view.currentItem, isNull);
      expect(view.resumed, isTrue);
    });

    test('expireStaleSessions 把超时会话的待答题目标记为过期', () async {
      final stale = await insertWord(term: 'stale');
      final fresh = await insertWord(term: 'fresh');
      final staleId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(stale), draft(stale)],
        now: now - sessionResumeTtlMs - 1,
      );
      final freshId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(fresh)],
        now: now,
      );

      final expired = await dao.expireStaleSessions(now);

      expect(expired, 2);
      final staleView = await dao.loadSession(staleId);
      expect(
        staleView.items.map((item) => item.status),
        everyElement(StudyItemStatus.skipped),
      );
      expect(
        staleView.items.map((item) => item.skipReason),
        everyElement('SESSION_EXPIRED'),
      );
      expect(staleView.completedAt, now);
      expect(staleView.durationMs, 0);

      final freshView = await dao.loadSession(freshId);
      expect(freshView.completedAt, isNull);
      expect(
        freshView.items.map((item) => item.status),
        everyElement(StudyItemStatus.pending),
      );
      // 会话过期是系统收尾，不算用户主动跳过，词条应立刻重新可学。
      final candidates = await dao.newCandidates(
        limit: 10,
        now: now,
        scope: CandidateScope.lexical,
      );
      expect(candidates.map((item) => item.id), <int>[stale]);
    });

    test('expireStaleSessions 对全部已完成的会话返回 0', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await insertSession(
        startedAt: now - sessionResumeTtlMs - 1,
      );
      await insertItem(sessionId, word, status: StudyItemStatus.answered);
      await insertItem(
        sessionId,
        word,
        position: 1,
        status: StudyItemStatus.skipped,
        answeredAt: now,
      );

      expect(await dao.expireStaleSessions(now), 0);
    });
  });

  group('会话恢复', () {
    test('findResumableSession 按会话类型恢复，类型不匹配返回 null', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await dao.createSession(
        mode: StudyMode.dueReview,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(word)],
        now: now,
      );

      expect(
        await dao.findResumableSession(StudyMode.dueReview, now),
        sessionId,
      );
      expect(await dao.findResumableSession(StudyMode.spelling, now), isNull);
      expect(await dao.findResumableSession(StudyMode.listening, now), isNull);
    });

    test('findResumableSession 能在每日会话里按任务类型恢复', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[
          draft(word, taskType: StudyTaskType.newWord),
        ],
        now: now,
      );

      expect(
        await dao.findResumableSession(StudyMode.newWords, now),
        sessionId,
      );
    });

    test('findResumableSession 对 AI 推荐按 source_type 恢复', () async {
      final word = await insertWord(term: 'apple');
      // 旧版把 AI 推荐的 session_type 落成 WRONG_WORDS，只有 source_type
      // 能还原真实模式。
      final sessionId = await dao.createSession(
        mode: StudyMode.wrongWords,
        sourceType: StudyMode.aiRecommended.wire,
        items: <StudySessionItemDraft>[
          draft(word, taskType: StudyTaskType.wrong),
        ],
        now: now,
      );

      expect(
        await dao.findResumableSession(StudyMode.aiRecommended, now),
        sessionId,
      );
      final view = await dao.loadSession(sessionId);
      expect(view.mode, StudyMode.aiRecommended);
      expect(view.sourceType, StudyMode.aiRecommended.wire);
    });

    test('findResumableSession 忽略已完成、超时与无待答题目的会话', () async {
      final word = await insertWord(term: 'apple');
      final completed = await insertSession(completedAt: now);
      await insertItem(completed, word);
      final stale = await insertSession(
        startedAt: now - sessionResumeTtlMs - 1,
      );
      await insertItem(stale, word);
      final answered = await insertSession();
      await insertItem(
        answered,
        word,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );

      expect(await dao.findResumableSession(StudyMode.dueReview, now), isNull);
    });
  });

  group('会话内的位置与计数', () {
    test('insertFollowUpItem 追加题目并增加计划题数', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await dao.createSession(
        mode: StudyMode.daily,
        sourceType: null,
        items: <StudySessionItemDraft>[draft(word)],
        now: now,
      );

      final position = await dao.insertFollowUpItem(
        sessionId: sessionId,
        wordId: word,
        questionType: QuestionType.zhToEnSpelling,
        position: sessionItemPositionStep,
        now: now,
      );

      expect(position, sessionItemPositionStep);
      expect(await dao.lastItemPosition(sessionId), sessionItemPositionStep);
      expect(
        await dao.findItemPosition(sessionId: sessionId, itemId: 999),
        isNull,
      );

      final view = await dao.loadSession(sessionId);
      expect(view.items, hasLength(2));
      expect(view.plannedCount, 2);
      expect(view.items.last.taskType, StudyTaskType.wrong);
      expect(
        await dao.findItemPosition(
          sessionId: sessionId,
          itemId: view.items.last.itemId,
        ),
        sessionItemPositionStep,
      );
    });

    test('lastItemPosition 对空会话返回 null', () async {
      final sessionId = await insertSession();

      expect(await dao.lastItemPosition(sessionId), isNull);
    });

    test('positionAtOffset 与 previousPositionBefore 定位相邻题目', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await insertSession();
      for (var index = 0; index < 4; index += 1) {
        await insertItem(
          sessionId,
          word,
          position: index * sessionItemPositionStep,
        );
      }

      expect(
        await dao.positionAtOffset(
          sessionId: sessionId,
          afterPosition: 0,
          offset: 0,
        ),
        sessionItemPositionStep,
      );
      expect(
        await dao.positionAtOffset(
          sessionId: sessionId,
          afterPosition: 0,
          offset: 2,
        ),
        3 * sessionItemPositionStep,
      );
      expect(
        await dao.positionAtOffset(
          sessionId: sessionId,
          afterPosition: 0,
          offset: 3,
        ),
        isNull,
      );
      expect(
        await dao.previousPositionBefore(
          sessionId: sessionId,
          position: 3 * sessionItemPositionStep,
        ),
        2 * sessionItemPositionStep,
      );
      expect(
        await dao.previousPositionBefore(sessionId: sessionId, position: 0),
        isNull,
      );
    });

    test('answeredCountInSession 与 pendingCountInSession 按词条统计', () async {
      final alpha = await insertWord(term: 'alpha');
      final bravo = await insertWord(term: 'bravo');
      final sessionId = await insertSession();
      await insertItem(
        sessionId,
        alpha,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );
      await insertItem(sessionId, alpha, position: 1);
      await insertItem(sessionId, bravo, position: 2);

      expect(
        await dao.answeredCountInSession(sessionId: sessionId, wordId: alpha),
        1,
      );
      expect(
        await dao.pendingCountInSession(sessionId: sessionId, wordId: alpha),
        1,
      );
      expect(
        await dao.pendingCountInSession(sessionId: sessionId, wordId: bravo),
        1,
      );
      expect(
        await dao.answeredCountInSession(sessionId: sessionId, wordId: bravo),
        0,
      );
    });

    test('findSessionHead 返回完成时间与来源', () async {
      final sessionId = await insertSession(
        mode: StudyMode.wrongWords,
        sourceType: StudyMode.aiRecommended.wire,
        completedAt: now,
      );

      final head = await dao.findSessionHead(sessionId);

      expect(head, isNotNull);
      expect(head!.completedAt, now);
      expect(head.sourceType, StudyMode.aiRecommended.wire);
      expect(head.sessionType, StudyMode.wrongWords.wire);
      expect(head.startedAt, now);
      expect(await dao.findSessionHead(999), isNull);
    });

    test('incrementPlannedCount 与 incrementSkippedCount 累加会话计数', () async {
      final sessionId = await insertSession();

      await dao.incrementPlannedCount(sessionId);
      await dao.incrementSkippedCount(sessionId);

      final row = await db
          .customSelect(
            'SELECT planned_count, skipped_count, completed_count '
            'FROM study_sessions WHERE id = ?',
            variables: <Variable<Object>>[Variable<int>(sessionId)],
          )
          .getSingle();
      expect(row.read<int>('planned_count'), 1);
      expect(row.read<int>('skipped_count'), 1);
      expect(row.read<int>('completed_count'), 1);
    });
  });

  group('干扰项来源', () {
    test('byTerms 命中易混词并过滤空释义与自身', () async {
      final target = await insertWord(term: 'apple');
      final pear = await insertWord(
        term: 'pear',
        definitionsJson: '[{"language":"zh","text":"梨"}]',
      );
      await insertWord(term: 'grape', definitionsJson: '[]');

      final rows = await dao.byTerms(<String>[
        'pear',
        'grape',
        'apple',
      ], target);

      expect(rows.map((row) => row.wordId), <int>[pear]);
      expect(rows.single.term, 'pear');
      expect(rows.single.definitionsJson, contains('梨'));
    });

    test('byTerms 对空词表直接返回空', () async {
      final target = await insertWord(term: 'apple');

      expect(await dao.byTerms(const <String>[], target), isEmpty);
    });

    test('activeWrongWords 只取活跃错词并排除自身', () async {
      final target = await insertWord(term: 'apple');
      final wrong = await insertWord(
        term: 'pear',
        definitionsJson: '[{"language":"zh","text":"梨"}]',
      );
      await insertWrongState(wrong, wrongCount: 4);
      await insertWrongState(target, wrongCount: 9);

      final rows = await dao.activeWrongWords(target);

      expect(rows.map((row) => row.wordId), <int>[wrong]);
    });

    test('activeWrongWords 过滤空释义与已暂停词条', () async {
      final target = await insertWord(term: 'apple');
      final empty = await insertWord(term: 'grape', definitionsJson: '[]');
      final suspended = await insertWord(term: 'plum', isSuspended: true);
      await insertWrongState(empty);
      await insertWrongState(suspended);

      expect(await dao.activeWrongWords(target), isEmpty);
    });

    test('randomPool 排除指定词条并过滤空释义', () async {
      final target = await insertWord(term: 'apple');
      final pear = await insertWord(term: 'pear');
      final grape = await insertWord(term: 'grape');
      await insertWord(term: 'empty', definitionsJson: '[]');

      final rows = await dao.randomPool(<int>{target}, 2);

      expect(
        rows.map((row) => row.wordId),
        unorderedEquals(<int>[pear, grape]),
      );
    });

    test('hasExampleMap 只认带非空句子的例句', () async {
      final withExample = await insertWord(
        term: 'alpha',
        examplesJson: '[{"sentence":"I eat an apple."}]',
      );
      final blank = await insertWord(
        term: 'bravo',
        examplesJson: '[{"sentence":"  "}]',
      );
      final broken = await insertWord(term: 'charlie', examplesJson: 'nope');
      final none = await insertWord(term: 'delta');

      final map = await dao.hasExampleMap(<int>[
        withExample,
        blank,
        broken,
        none,
        999,
      ]);

      expect(map[withExample], isTrue);
      expect(map[blank], isFalse);
      expect(map[broken], isFalse);
      expect(map[none], isFalse);
      expect(map[999], isFalse);
    });
  });

  group('配额与每日计划', () {
    test('countAvailable 与 loadPools 的数字自洽', () async {
      final due = await insertWord(term: 'due');
      await insertCard(due, dueAt: now - dayMs);
      final wrong = await insertWord(term: 'wrong');
      await insertWrongState(wrong);
      final fresh = await insertWord(term: 'fresh');

      final availability = await dao.countAvailable(
        now: now,
        scope: CandidateScope.lexical,
      );
      expect(availability.due, 1);
      expect(availability.wrong, 1);
      // 错词没有 review_cards 行，因此同时算「从未复习过」的新词。
      expect(availability.fresh, 2);

      final pools = await dao.loadPools(
        now: now,
        scope: CandidateScope.lexical,
      );
      // loadPools 会按「配额 + 三池配额之和」多取候选，供抽题去重后仍够用。
      const buffer =
          defaultDailyDueReviewLimit +
          defaultDailyWrongWordLimit +
          defaultDailyNewWords;
      expect(pools.limits.due, defaultDailyDueReviewLimit);
      expect(pools.limits.wrong, defaultDailyWrongWordLimit);
      expect(pools.limits.fresh, defaultDailyNewWords);
      expect(pools.due.length, lessThanOrEqualTo(pools.limits.due + buffer));
      expect(
        pools.wrong.length,
        lessThanOrEqualTo(pools.limits.wrong + buffer),
      );
      expect(
        pools.fresh.length,
        lessThanOrEqualTo(pools.limits.fresh + buffer),
      );
      expect(
        pools.length,
        availability.due + availability.wrong + availability.fresh,
      );
      expect(pools.due.map((item) => item.id), <int>[due]);
      expect(pools.wrong.map((item) => item.id), <int>[wrong]);
      expect(
        pools.fresh.map((item) => item.id),
        unorderedEquals(<int>[wrong, fresh]),
      );
    });

    test('loadPools 的配额来自设置', () async {
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'dailyNewWords',
              valueJson: '3',
              updatedAt: now,
            ),
          );

      final pools = await dao.loadPools(
        now: now,
        scope: CandidateScope.lexical,
      );

      expect(pools.limits.fresh, 3);
    });

    test('applyDailySoftQuota 按今日进度扣减配额', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await insertSession();
      for (var index = 0; index < defaultDailyNewWords; index += 1) {
        await insertItem(
          sessionId,
          word,
          position: index.toDouble(),
          taskType: StudyTaskType.newWord,
          status: StudyItemStatus.answered,
          answeredAt: now,
        );
      }

      final pools = await dao.loadPools(
        now: now,
        scope: CandidateScope.lexical,
        applyDailySoftQuota: true,
      );

      // 用满配额后只留 dailyQuotaGraceRatio 的宽限，而不是直接归零。
      expect(
        pools.limits.fresh,
        (defaultDailyNewWords * dailyQuotaGraceRatio).ceil(),
      );
      expect(pools.limits.due, defaultDailyDueReviewLimit);
    });

    test('applyDailySoftQuota 对句子范围不生效', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await insertSession();
      await insertItem(
        sessionId,
        word,
        taskType: StudyTaskType.newWord,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );

      final pools = await dao.loadPools(
        now: now,
        scope: CandidateScope.sentence,
        applyDailySoftQuota: true,
      );

      expect(pools.limits.fresh, defaultDailyNewWords);
    });

    test('dailyProgress 只统计今天的每日会话', () async {
      final word = await insertWord(term: 'apple');
      final daily = await insertSession();
      await insertItem(
        daily,
        word,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );
      await insertItem(
        daily,
        word,
        position: 1,
        taskType: StudyTaskType.wrong,
        status: StudyItemStatus.skipped,
        answeredAt: now,
        skipReason: 'LATER',
      );
      await insertItem(
        daily,
        word,
        position: 2,
        taskType: StudyTaskType.newWord,
      );
      // 昨天的题目不计入
      final yesterday = await insertSession();
      await insertItem(
        yesterday,
        word,
        status: StudyItemStatus.answered,
        answeredAt: now - dayMs,
      );
      // 非每日会话不计入
      final wrongMode = await insertSession(mode: StudyMode.wrongWords);
      await insertItem(
        wrongMode,
        word,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );

      final progress = await dao.dailyProgress(now);

      expect(progress.due, 1);
      expect(progress.wrong, 1);
      expect(progress.fresh, 1);
    });

    test('dailyProgress 忽略听力与拼写任务', () async {
      final word = await insertWord(term: 'apple');
      final sessionId = await insertSession();
      await insertItem(
        sessionId,
        word,
        taskType: StudyTaskType.listening,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );
      await insertItem(
        sessionId,
        word,
        position: 1,
        taskType: StudyTaskType.spelling,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );

      final progress = await dao.dailyProgress(now);

      expect(progress.due, 0);
      expect(progress.wrong, 0);
      expect(progress.fresh, 0);
    });

    test('activePendingPlan 按类别统计未完成会话里的待答题目', () async {
      final dueWord = await insertWord(term: 'due');
      final wrongWord = await insertWord(term: 'wrong');
      final freshWord = await insertWord(term: 'fresh');
      await insertCard(dueWord, dueAt: now - dayMs);
      await insertWrongState(wrongWord);
      final sessionId = await insertSession();
      await insertItem(sessionId, dueWord);
      await insertItem(sessionId, wrongWord, position: 1);
      await insertItem(sessionId, freshWord, position: 2);

      final plan = await dao.activePendingPlan(now);

      expect(plan.due, 1);
      expect(plan.wrong, 1);
      expect(plan.fresh, 1);
    });

    test('activePendingPlan 未到期的卡片算作新词', () async {
      final word = await insertWord(term: 'apple');
      await insertCard(word, dueAt: now + dayMs);
      final sessionId = await insertSession();
      await insertItem(sessionId, word);

      final plan = await dao.activePendingPlan(now);

      expect(plan.due, 0);
      expect(plan.wrong, 0);
      expect(plan.fresh, 1);
    });

    test('activePendingPlan 忽略已完成、超时、小游戏与句子会话', () async {
      final word = await insertWord(term: 'apple');
      final sentence = await insertWord(
        term: 'The cat sat on the mat.',
        contentType: LexicalContentType.sentence,
        summaryJson: '{"translation":"猫坐在垫子上。"}',
      );
      final completed = await insertSession(completedAt: now);
      await insertItem(completed, word);
      final stale = await insertSession(
        startedAt: now - sessionResumeTtlMs - 1,
      );
      await insertItem(stale, word);
      final game = await insertSession(sourceType: 'GAME_MATCH');
      await insertItem(game, word);
      final sentenceSession = await insertSession(
        mode: StudyMode.sentenceReview,
        sourceType: StudyMode.sentenceReview.wire,
      );
      await insertItem(sentenceSession, sentence);
      // 已作答的题目也不算
      final answered = await insertSession();
      await insertItem(
        answered,
        word,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );

      final plan = await dao.activePendingPlan(now);

      expect(plan.due, 0);
      expect(plan.wrong, 0);
      expect(plan.fresh, 0);
    });

    test('activePendingSentenceCount 只统计句子复习会话', () async {
      final sentence = await insertWord(
        term: 'The cat sat on the mat.',
        contentType: LexicalContentType.sentence,
        summaryJson: '{"translation":"猫坐在垫子上。"}',
      );
      final word = await insertWord(term: 'apple');
      final sentenceSession = await insertSession(
        mode: StudyMode.sentenceReview,
        sourceType: StudyMode.sentenceReview.wire,
      );
      await insertItem(sentenceSession, sentence);
      await insertItem(
        sentenceSession,
        sentence,
        position: 1,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );
      final daily = await insertSession();
      await insertItem(daily, word);

      expect(await dao.activePendingSentenceCount(now), 1);
    });

    test('activePendingSentenceCount 忽略已完成与超时的会话', () async {
      final sentence = await insertWord(
        term: 'The cat sat on the mat.',
        contentType: LexicalContentType.sentence,
        summaryJson: '{"translation":"猫坐在垫子上。"}',
      );
      final completed = await insertSession(
        mode: StudyMode.sentenceReview,
        sourceType: StudyMode.sentenceReview.wire,
        completedAt: now,
      );
      await insertItem(completed, sentence);
      final stale = await insertSession(
        mode: StudyMode.sentenceReview,
        sourceType: StudyMode.sentenceReview.wire,
        startedAt: now - sessionResumeTtlMs - 1,
      );
      await insertItem(stale, sentence);
      // 每日会话里的句子不算句子复习进度
      final daily = await insertSession();
      await insertItem(daily, sentence);

      expect(await dao.activePendingSentenceCount(now), 0);
    });
  });

  group('AI 推荐', () {
    test('aiRecommendedCandidates 读取今日建议并带上题型', () async {
      final first = await insertWord(term: 'alpha');
      final second = await insertWord(term: 'bravo');
      await db
          .into(db.dailyAiSuggestions)
          .insert(
            DailyAiSuggestionsCompanion.insert(
              dateKey: dateKey(now),
              sourceDateKey: dateKey(now),
              recommendedItemsJson: Value<String>(
                '[{"wordId":$first,"questionType":"EN_TO_ZH_CHOICE"},'
                '{"wordId":$second,"questionType":"ZH_TO_EN_SPELLING"}]',
              ),
              generatedAt: now,
              updatedAt: now,
            ),
          );

      final candidates = await dao.aiRecommendedCandidates(now);

      expect(candidates.map((item) => item.id), <int>[first, second]);
      expect(
        candidates.first.recommendedQuestionType,
        QuestionType.enToZhChoice,
      );
      expect(
        candidates.last.recommendedQuestionType,
        QuestionType.zhToEnSpelling,
      );
    });

    test('aiRecommendedCandidates 排除今天已在 AI 会话里做过的词条', () async {
      final done = await insertWord(term: 'alpha');
      final remaining = await insertWord(term: 'bravo');
      await db
          .into(db.dailyAiSuggestions)
          .insert(
            DailyAiSuggestionsCompanion.insert(
              dateKey: dateKey(now),
              sourceDateKey: dateKey(now),
              recommendedItemsJson: Value<String>(
                '[{"wordId":$done,"questionType":"EN_TO_ZH_CHOICE"},'
                '{"wordId":$remaining,"questionType":"EN_TO_ZH_CHOICE"}]',
              ),
              generatedAt: now,
              updatedAt: now,
            ),
          );
      final sessionId = await insertSession(
        mode: StudyMode.wrongWords,
        sourceType: StudyMode.aiRecommended.wire,
      );
      await insertItem(
        sessionId,
        done,
        taskType: StudyTaskType.wrong,
        status: StudyItemStatus.answered,
        answeredAt: now,
      );

      final candidates = await dao.aiRecommendedCandidates(now);

      expect(candidates.map((item) => item.id), <int>[remaining]);
    });

    test('aiRecommendedCandidates 在没有建议或 JSON 损坏时返回空', () async {
      await insertWord(term: 'alpha');

      expect(await dao.aiRecommendedCandidates(now), isEmpty);

      await db
          .into(db.dailyAiSuggestions)
          .insert(
            DailyAiSuggestionsCompanion.insert(
              dateKey: dateKey(now),
              sourceDateKey: dateKey(now),
              recommendedItemsJson: const Value<String>('not-json'),
              generatedAt: now,
              updatedAt: now,
            ),
          );

      expect(await dao.aiRecommendedCandidates(now), isEmpty);
    });

    test('aiRecommendedCandidates 过滤不可学习的词条', () async {
      final suspended = await insertWord(term: 'alpha', isSuspended: true);
      final empty = await insertWord(term: 'bravo', definitionsJson: '[]');
      await db
          .into(db.dailyAiSuggestions)
          .insert(
            DailyAiSuggestionsCompanion.insert(
              dateKey: dateKey(now),
              sourceDateKey: dateKey(now),
              recommendedItemsJson: Value<String>(
                '[{"wordId":$suspended,"questionType":"EN_TO_ZH_CHOICE"},'
                '{"wordId":$empty,"questionType":"EN_TO_ZH_CHOICE"}]',
              ),
              generatedAt: now,
              updatedAt: now,
            ),
          );

      expect(await dao.aiRecommendedCandidates(now), isEmpty);
    });
  });

  group('干扰项接口契约', () {
    test('StudyDao 实现 DistractorSource', () {
      expect(dao, isA<DistractorSource>());
    });
  });
}
