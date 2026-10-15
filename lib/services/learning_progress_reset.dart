/// 「重置本次导入已有词条的学习进度」的共享实现。
///
/// **为什么必须共享**：旧版只有一份 `commitImport`
/// （`src/modules/imports/commit.ts:92-96`），CSV 导入与文章导入都调它；
/// 本版的 CSV 路径把这段写在了 `CsvImportService` 私有方法里，文章导入
/// 路径于是拿不到它——旧版文章导入界面上的「重置本次已有词条的学习进度」
/// 开关（`components/add/article-tab.tsx:475,526`）因此无法实现。
/// 重置会**不可逆地删除复习历史**，两处各写一份迟早会在「删哪几张表」
/// 上漂移，所以这里收敛成唯一实现。
///
/// 提供两个入口：
/// - [writeProgressReset]：往调用方已经开好的 [Batch] 里追加语句。
///   CSV 导入整批一个事务，用它才不会把一次导入拆成多个事务；
/// - [resetLearningProgressNow]：调用方没有批次时直接执行。
///   文章导入逐条走 `WordEditService`（每条各自事务），用这个。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/enums.dart';

/// `study_session_items.skip_reason`：因导入勾选了「重置学习进度」而撤下的题目。
///
/// **字面量必须与旧版 `src/modules/imports/commit.ts` 的 `'PROGRESS_RESET'`
/// 逐字符一致**：`core/constants.dart` 里 `wordSuspendedSkipReason` 的表级文档
/// 已经写明，跳过原因参与 `study_dao.dart` 的 `_availabilitySql` 候选排除
/// （`SESSION_EXPIRED` / `PROGRESS_RESET` 属系统收尾，不算用户意愿），
/// 备份回放与跨端统计也按该字符串分组；换一个字面量等于让历史会话的
/// 聚合统计对不上。
const String progressResetSkipReason = 'PROGRESS_RESET';

/// 本次导入是否需要重置学习进度；返回重置时间戳或 `null`。
///
/// `SKIP_EXISTING` 模式下不重置：那一整个分支的语义是「已有的词条完全不动」，
/// 连学习进度一起重置会与该模式的名字矛盾。
int? resetAtFor(ImportMode mode, {required bool requested, required int now}) =>
    mode == ImportMode.skipExisting || !requested ? null : now;

/// 把「清空一个已有词条的学习进度」的语句追加到 [batch]。
///
/// 六条语句与旧版 `commit.ts:92-96` 对应，外加一条本版才需要的：
///
/// 1. `review_logs` / `review_cards` / `wrong_word_states` 整行删除——
///    复习卡与错词状态都只是 `review_logs` 的物化，删日志必然要连带删；
/// 2. `study_session_items` 里该词条**未作答**的题目标记为 `SKIPPED`，
///    `skip_reason` 记 [progressResetSkipReason]：一道已经作答的题保留原状，
///    它属于学习历史，不该被这次导入改写；
/// 3. `words` 的掌握度归零，否则词条仍会以「已掌握」的姿态留在词库里，
///    而它的复习卡已经不存在了；
/// 4. `word_review_stats` 整行删除——**这条是本版新增的**：该表是
///    `review_logs` 的聚合缓存，学习队列与游戏选词都用 `LEFT JOIN` 读它。
///    只删日志会留下一份说「复习过 200 次」的陈旧统计，让队列继续给一个
///    进度已被重置的词条加权。缺行在所有读点都等价于「没有历史」。
void writeProgressReset(
  Batch batch, {
  required AppDatabase db,
  required int wordId,
  required int now,
}) {
  batch
    ..deleteWhere(db.reviewLogs, (t) => t.wordId.equals(wordId))
    ..deleteWhere(db.reviewCards, (t) => t.wordId.equals(wordId))
    ..deleteWhere(db.wrongWordStates, (t) => t.wordId.equals(wordId))
    ..deleteWhere(db.wordReviewStats, (t) => t.wordId.equals(wordId))
    ..update(
      db.studySessionItems,
      StudySessionItemsCompanion(
        status: const Value(StudyItemStatus.skipped),
        answeredAt: Value(now),
        skipReason: const Value(progressResetSkipReason),
      ),
      where: (t) =>
          t.wordId.equals(wordId) &
          t.status.equalsValue(StudyItemStatus.pending),
    )
    ..update(
      db.words,
      WordsCompanion(
        masteryLevel: const Value(MasteryLevel.newWord),
        masteryScore: const Value(0),
        updatedAt: Value(now),
      ),
      where: (t) => t.id.equals(wordId),
    );
}

/// 立刻清空一个已有词条的学习进度。
///
/// 逐条写入的导入路径（文章导入）用这个；整批一个事务的 CSV 路径请用
/// [writeProgressReset] 把语句并进它自己的批次。
Future<void> resetLearningProgressNow({
  required AppDatabase db,
  required int wordId,
  required int now,
}) async {
  await db.batch((batch) {
    writeProgressReset(batch, db: db, wordId: wordId, now: now);
  });
}
