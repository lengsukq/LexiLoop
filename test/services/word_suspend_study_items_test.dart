/// 暂停词条时撤下待答题的单测。
///
/// **为什么单独立一个文件**：暂停不只是改一个布尔位——它还必须把该词条
/// 在各会话里的待答题撤下、把会话计数补齐、收尾被抽空的会话。
/// 这里是「词条」与「学习队列」两条历史的交界处，独立成文件才能一眼看清
/// 契约：撤下的题带 `WORD_SUSPENDED` 原因、会话计数跟着涨、
/// 恢复学习不会把它们放回来。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/word_edit_service.dart';

void main() {
  late AppDatabase db;
  late WordEditService service;
  late StudyDao studyDao;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    service = WordEditService(db);
    studyDao = StudyDao(db);
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> createWord(String term) => service.create(
    draft: WordDraft(
      term: term,
      contentType: LexicalContentType.word,
      sourceLanguage: 'en',
      targetLanguage: 'zh',
      definitions: const <String>['释义'],
    ),
    now: now,
  );

  /// 建一个装满待答题的会话；同一词条重复出现即多道题。
  Future<int> sessionOf(List<int> wordIds) => studyDao.createSession(
    mode: StudyMode.daily,
    sourceType: null,
    items: <StudySessionItemDraft>[
      for (final wordId in wordIds)
        StudySessionItemDraft(
          wordId: wordId,
          taskType: StudyTaskType.review,
          questionType: QuestionType.enToZhChoice,
        ),
    ],
    now: now,
  );

  Future<List<StudySessionItemRow>> itemsIn(int sessionId) {
    return (db.select(db.studySessionItems)
          ..where((row) => row.studySessionId.equals(sessionId))
          ..orderBy([(row) => OrderingTerm.asc(row.position)]))
        .get();
  }

  Future<StudySessionRow> sessionRow(int sessionId) {
    return (db.select(
      db.studySessions,
    )..where((row) => row.id.equals(sessionId))).getSingle();
  }

  Future<WordRow> wordRow(int wordId) {
    return (db.select(
      db.words,
    )..where((row) => row.id.equals(wordId))).getSingle();
  }

  /// 直接把一道题标成已作答，绕开作答流程以便构造前置状态。
  Future<void> markAnswered(int itemId, int answeredAt) async {
    await (db.update(
      db.studySessionItems,
    )..where((row) => row.id.equals(itemId))).write(
      StudySessionItemsCompanion(
        status: const Value<StudyItemStatus>(StudyItemStatus.answered),
        answeredAt: Value<int>(answeredAt),
      ),
    );
  }

  test('暂停把待答题改成 SKIPPED，原因与作答时间都被写入', () async {
    final wordId = await createWord('apple');
    final sessionId = await sessionOf(<int>[wordId]);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    final item = (await itemsIn(sessionId)).single;
    expect(item.status, StudyItemStatus.skipped);
    expect(item.skipReason, wordSuspendedSkipReason);
    expect(item.skipReason, 'WORD_SUSPENDED');
    expect(item.answeredAt, now);
    expect((await db.select(db.words).get()).single.isSuspended, isTrue);
  });

  test('会话的完成数与跳过数按撤下的题数递增', () async {
    final wordId = await createWord('apple');
    final other = await createWord('banana');
    final sessionId = await sessionOf(<int>[wordId, wordId, other]);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    final session = await sessionRow(sessionId);
    expect(session.completedCount, 2);
    expect(session.skippedCount, 2);
    expect(session.correctCount, 0);
    expect(session.wrongCount, 0);
  });

  test('被撤空且没有其它待答题的会话被收尾', () async {
    final wordId = await createWord('apple');
    final sessionId = await sessionOf(<int>[wordId]);
    expect((await sessionRow(sessionId)).completedAt, isNull);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    final session = await sessionRow(sessionId);
    expect(session.completedAt, now);
    expect(session.durationMs, 0, reason: '没有作答日志，有效时长应为 0');
  });

  test('会话里还有别的待答题时保持未完成', () async {
    final wordId = await createWord('apple');
    final other = await createWord('banana');
    final sessionId = await sessionOf(<int>[wordId, other]);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    expect((await sessionRow(sessionId)).completedAt, isNull);
  });

  test('已作答的题目不被改写', () async {
    final wordId = await createWord('apple');
    final sessionId = await sessionOf(<int>[wordId, wordId]);
    final answeredAt = now - 1;
    await markAnswered((await itemsIn(sessionId)).first.id, answeredAt);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    final items = await itemsIn(sessionId);
    expect(items.first.status, StudyItemStatus.answered);
    expect(items.first.answeredAt, answeredAt);
    expect(items.first.skipReason, isNull);
    expect(items.last.status, StudyItemStatus.skipped);
    final session = await sessionRow(sessionId);
    expect(session.skippedCount, 1, reason: '只有撤下的那题算跳过');
    expect(session.completedAt, now, reason: '最后一道待答题被撤下后会话即无待答题，应收尾');
  });

  test('恢复学习不会把撤下的题目放回队列', () async {
    final wordId = await createWord('apple');
    final sessionId = await sessionOf(<int>[wordId]);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);
    await service.setSuspended(wordId: wordId, suspended: false, now: now + 1);

    final item = (await itemsIn(sessionId)).single;
    expect(item.status, StudyItemStatus.skipped);
    expect(item.skipReason, wordSuspendedSkipReason);
    final session = await sessionRow(sessionId);
    expect(session.completedCount, 1);
    expect(session.skippedCount, 1);
    expect((await db.select(db.words).get()).single.isSuspended, isFalse);
  });

  test('没有待答题的词条被暂停是空操作', () async {
    final wordId = await createWord('apple');
    final other = await createWord('banana');
    final sessionId = await sessionOf(<int>[other]);
    final before = await sessionRow(sessionId);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    expect((await wordRow(wordId)).isSuspended, isTrue);
    final after = await sessionRow(sessionId);
    expect(after.completedCount, before.completedCount);
    expect(after.skippedCount, before.skippedCount);
    expect(after.completedAt, before.completedAt);
    final item = (await itemsIn(sessionId)).single;
    expect(item.status, StudyItemStatus.pending);
    expect(item.skipReason, isNull);
  });

  test('别的词条在同一会话里的题目不受影响', () async {
    final wordId = await createWord('apple');
    final other = await createWord('banana');
    final sessionId = await sessionOf(<int>[wordId, other]);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    final items = await itemsIn(sessionId);
    expect(items.first.wordId, wordId);
    expect(items.first.status, StudyItemStatus.skipped);
    expect(items.last.wordId, other);
    expect(items.last.status, StudyItemStatus.pending);
    expect(items.last.skipReason, isNull);
    expect(items.last.answeredAt, isNull);
  });

  test('同一条目跨多个会话的待答题都被撤下并分别计数', () async {
    final wordId = await createWord('apple');
    final first = await sessionOf(<int>[wordId]);
    final second = await sessionOf(<int>[wordId, wordId]);

    await service.setSuspended(wordId: wordId, suspended: true, now: now);

    final single = await sessionRow(first);
    expect(single.skippedCount, 1);
    expect(single.completedCount, 1);
    expect(single.completedAt, now);
    final pair = await sessionRow(second);
    expect(pair.skippedCount, 2);
    expect(pair.completedCount, 2);
    expect(pair.completedAt, now);
    for (final row in <StudySessionItemRow>[
      ...await itemsIn(first),
      ...await itemsIn(second),
    ]) {
      expect(row.status, StudyItemStatus.skipped);
      expect(row.skipReason, 'WORD_SUSPENDED');
      expect(row.answeredAt, now);
    }
  });
}
