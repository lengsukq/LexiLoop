/// 词条详情页的数据提供者与写操作。
///
/// **取数与渲染分离**：页面组件只 `watch` 这里的数据提供者、只调用
/// [WordDetailActions] 的方法，不直接接触 Drift。旧版详情页把取数放在
/// `use-word-detail.ts`、又在组件里重复了一遍解析逻辑，还向下传了
/// 11 + 6 + 7 个回调 props；这里用「一个数据提供者 + 一个行为对象」收敛。
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/features/words/words_providers.dart';

/// 词条详情查询。
final Provider<WordDetailDao> wordDetailDaoProvider = Provider<WordDetailDao>(
  (ref) => WordDetailDao(ref.watch(databaseProvider)),
);

/// 单个词条的详情；词条不存在时数据为 `null`。
final FutureProviderFamily<WordDetail?, int> wordDetailProvider =
    FutureProvider.family<WordDetail?, int>(
      (ref, wordId) => ref.watch(wordDetailDaoProvider).find(wordId),
    );

/// 单个词条的复习统计与卡片状态。
final FutureProviderFamily<WordLearningSnapshot, int>
wordLearningSnapshotProvider = FutureProvider.family<WordLearningSnapshot, int>(
  (ref, wordId) => ref.watch(wordDetailDaoProvider).learningSnapshot(wordId),
);

/// 单个词条的最近复习记录。
final FutureProviderFamily<List<ReviewLogEntry>, int> recentReviewLogsProvider =
    FutureProvider.family<List<ReviewLogEntry>, int>(
      (ref, wordId) => ref.watch(wordDetailDaoProvider).recentLogs(wordId),
    );

/// 详情页展示用的首选发音口音。
///
/// 设置尚未加载完成时退回 [Accent.us]，与 `AppSettings.defaults` 一致，
/// 避免详情页的音标先显示英音再跳成美音。
final Provider<Accent> preferredAccentProvider = Provider<Accent>((ref) {
  final settings = ref.watch(appSettingsProvider).value;
  return settings?.playback.defaultAccent ?? Accent.us;
});

/// 词条详情的写操作入口。
final Provider<WordDetailActions> wordDetailActionsProvider =
    Provider<WordDetailActions>(WordDetailActions.new);

/// 词条详情的写操作（暂停、笔记、删除）。
///
/// 只有「容器引用」一个依赖，不接收回调参数——行为对象而非回调集合，
/// 是旧版详情页参数膨胀（11 + 6 + 7 个 props）的直接对策。
class WordDetailActions {
  /// 以容器引用构造。
  const new(this._ref);

  final Ref _ref;

  /// 切换「暂停学习」。
  ///
  /// 时间戳在方法内部取：写操作只需要一个「现在」，为它多开一个参数
  /// 只会让每个调用点都要先算一遍当前时间。
  Future<void> setSuspended(int wordId, {required bool suspended}) async {
    final db = _ref.read(databaseProvider);
    await (db.update(db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        isSuspended: Value<bool>(suspended),
        updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    _invalidateWord(wordId);
  }

  /// 保存笔记；空白内容写回 `null`，避免留下一个「有笔记但看不见」的词条。
  Future<void> saveNote(int wordId, String note) async {
    final text = note.trim();
    final db = _ref.read(databaseProvider);
    await (db.update(db.words)..where((row) => row.id.equals(wordId))).write(
      WordsCompanion(
        userNote: Value<String?>(text.isEmpty ? null : text),
        updatedAt: Value<int>(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    _invalidateWord(wordId);
  }

  /// 删除词条。
  ///
  /// 内容、卡片、日志与错词状态由外键 `ON DELETE CASCADE` 一并清除
  /// （`beforeOpen` 里已 `PRAGMA foreign_keys = ON`），因此这里只删 `words`。
  Future<void> delete(int wordId) async {
    final db = _ref.read(databaseProvider);
    await (db.delete(db.words)..where((row) => row.id.equals(wordId))).go();
    _ref
      ..invalidate(wordDetailProvider(wordId))
      ..invalidate(wordLearningSnapshotProvider(wordId))
      ..invalidate(recentReviewLogsProvider(wordId))
      ..invalidate(dashboardOverviewProvider)
      ..invalidate(wordListProvider)
      ..invalidate(wordCountProvider)
      ..invalidate(masterySummaryProvider);
  }

  /// 失效该词条相关的全部缓存。
  ///
  /// 同时失效仪表盘概览：暂停与删除都会改变「今日到期」「新词可用」，
  /// 若只刷新详情页，用户切回首页会看到过期数字。
  void _invalidateWord(int wordId) {
    _ref
      ..invalidate(wordDetailProvider(wordId))
      ..invalidate(wordLearningSnapshotProvider(wordId))
      ..invalidate(recentReviewLogsProvider(wordId))
      ..invalidate(dashboardOverviewProvider);
  }
}
