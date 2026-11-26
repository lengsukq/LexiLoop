/// `DashboardOverview` 的查询测试。
///
/// **为什么放在 features/dashboard 下**：这组指标（今日完成度、今日正确率、
/// 初始化失败数）只为首页服务。断言写成「数据库里放了什么 → 概览读出什么」，
/// 而不是抄一遍 SQL 里的算式，否则查询写错了测试也会跟着一起错。
library;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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

  tearDown(() => db.close());

  /// 昨天：用来验证「只统计今日」的边界。
  final yesterday = DateTime(2026, 2, 28, 10).millisecondsSinceEpoch;

  /// 插入一个词条，返回其 ID。
  Future<int> insertWord({
    InitializationStatus status = InitializationStatus.ready,
    String term = 'apple',
  }) => db
      .into(db.words)
      .insert(
        WordsCompanion.insert(
          term: term,
          normalizedTerm: term,
          sourceLanguage: 'en',
          targetLanguage: 'zh',
          entryType: EntryType.word,
          initializationStatus: Value<InitializationStatus>(status),
          createdAt: now,
          updatedAt: now,
        ),
      );

  /// 写入一条复习记录。
  Future<void> insertLog({
    required int wordId,
    required int reviewedAt,
    required bool isCorrect,
    required String answerId,
  }) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          clientAnswerId: answerId,
          wordId: wordId,
          reviewedAt: reviewedAt,
          rating: ReviewRating.good,
          questionType: QuestionType.enToZh,
          isCorrect: isCorrect,
          createdAt: reviewedAt,
        ),
      );

  /// 写入一条「跳过」的会话题。
  ///
  /// [skipReason] 为 `null` 表示用户主动跳过（`LATER`）；系统收尾会带上
  /// `SESSION_EXPIRED` 之类的字面量。
  Future<void> insertSkipped({
    required int wordId,
    required int answeredAt,
    required double position,
    String? skipReason,
  }) async {
    final sessionId = await db
        .into(db.studySessions)
        .insert(
          StudySessionsCompanion.insert(
            sessionType: StudyMode.daily,
            startedAt: answeredAt,
            createdAt: answeredAt,
          ),
        );
    await db
        .into(db.studySessionItems)
        .insert(
          StudySessionItemsCompanion.insert(
            studySessionId: sessionId,
            position: position,
            wordId: wordId,
            taskType: StudyTaskType.newWord,
            questionType: QuestionType.enToZh,
            status: const Value<StudyItemStatus>(StudyItemStatus.skipped),
            answeredAt: Value<int>(answeredAt),
            skipReason: Value<String?>(skipReason),
            createdAt: answeredAt,
          ),
        );
  }

  test('今日计数只统计今天：正确率与已处理数', () async {
    final wordId = await insertWord();
    await insertLog(
      wordId: wordId,
      reviewedAt: now,
      isCorrect: true,
      answerId: 'a1',
    );
    await insertLog(
      wordId: wordId,
      reviewedAt: now - 1000,
      isCorrect: false,
      answerId: 'a2',
    );
    await insertLog(
      wordId: wordId,
      reviewedAt: yesterday,
      isCorrect: false,
      answerId: 'a3',
    );

    final overview = await dao.overview(now);

    expect(overview.reviewedToday, 2, reason: '昨天的记录不计入今日');
    expect(overview.completedToday, 2);
    expect(overview.todayAccuracy, closeTo(0.5, 0.001));
  });

  test('主动跳过计入今日已处理，系统收尾的跳过不计入', () async {
    final wordId = await insertWord();
    await insertSkipped(wordId: wordId, answeredAt: now, position: 0);
    await insertSkipped(
      wordId: wordId,
      answeredAt: now,
      skipReason: 'SESSION_EXPIRED',
      position: 0.5,
    );

    expect((await dao.overview(now)).completedToday, 1);
  });

  test('今日没有作答时正确率为 0 而不是崩溃', () async {
    final overview = await dao.overview(now);

    expect(overview.completedToday, 0);
    expect(overview.todayAccuracy, 0);
  });

  test('目标总题数 = 今日已处理 + 计划剩余', () async {
    final wordId = await insertWord();
    await insertLog(
      wordId: wordId,
      reviewedAt: now,
      isCorrect: true,
      answerId: 'a1',
    );

    final overview = await dao.overview(now, plannedRemaining: 9);

    expect(overview.todayGoalTotal, 10);
  });

  test('初始化失败的词条计入 failedWords', () async {
    await insertWord(term: 'banana');
    await insertWord(term: 'broken', status: InitializationStatus.failed);

    expect((await dao.overview(now)).failedWords, 1);
  });
}
