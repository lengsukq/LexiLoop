/// 本地数据重置。
///
/// 「清空全部数据」在设置页的危险区里，需要二次确认（输入 DELETE）。
/// 这里只负责把 15 张表按外键顺序清空——顺序不能随意调整，
/// SQLite 打开了外键约束，先删父表会直接失败。
library;

import 'package:lexiloop/data/db/database.dart';

/// 清空本地全部数据（含设置）。
///
/// 整个过程在**一个事务**内：要么全部清空，要么保持原样，
/// 否则中途失败会留下「词条没了但学习记录还在」的孤儿数据。
Future<void> clearAllData(AppDatabase db) async {
  await db.transaction(() async {
    await db.delete(db.providerAttempts).go();
    await db.delete(db.initializationJobs).go();
    await db.delete(db.importRows).go();
    await db.delete(db.importBatches).go();
    await db.delete(db.reviewLogs).go();
    await db.delete(db.wrongWordStates).go();
    await db.delete(db.reviewCards).go();
    await db.delete(db.studySessionItems).go();
    await db.delete(db.studySessions).go();
    await db.delete(db.wordContents).go();
    await db.delete(db.wordReviewStats).go();
    await db.delete(db.words).go();
    await db.delete(db.dailyAiSuggestions).go();
    await db.delete(db.gameHighScores).go();
    await db.delete(db.settings).go();
  });
}
