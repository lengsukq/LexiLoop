/// 词条列表的状态与数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/backup/backup_import.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/services/backup_service.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';

export 'package:lexiloop/ui/navigation/route_paths.dart' show statisticsPath;

/// 手动添加词条页的路径。
///
/// 与 `appDestinations` 里的 `/add` 对应；集中具名是为了让「入口按钮」
/// 与「路由断言」写的是同一个字符串。
const String addWordPath = addPath;

/// 备份导入服务。
final Provider<BackupService> backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(BackupImporter(ref.watch(databaseProvider))),
);

/// 关键词、筛选、排序与分页的控制器。
///
/// **所有会改变结果集的入口都走 [_apply]**，由它统一把页码复位到第一页。
/// 漏掉一次的后果很具体：用户在第 5 页改了筛选，结果只剩 2 条，
/// 分页条会显示「第 5 / 1 页」而列表是空的，看起来像应用坏了。
class WordQueryNotifier extends Notifier<WordQuery> {
  @override
  WordQuery build() => const WordQuery();

  /// 更新关键词搜索。
  void setSearch(String search) => _apply(state.copyWith(search: search));

  /// 切换掌握等级筛选（传 `null` 表示不筛选）。
  void setMasteryLevel(MasteryLevel? level) => _apply(
    state.copyWith(masteryLevel: level, clearMasteryLevel: level == null),
  );

  /// 切换初始化状态筛选（传 `null` 表示不筛选）。
  void setInitializationStatus(InitializationStatus? status) => _apply(
    state.copyWith(
      initializationStatus: status,
      clearInitializationStatus: status == null,
    ),
  );

  /// 只看 / 不看活跃错词。
  void setWrongOnly({required bool enabled}) =>
      _apply(state.copyWith(wrongOnly: enabled));

  /// 只看 / 不看到期复习。
  void setDueOnly({required bool enabled}) =>
      _apply(state.copyWith(dueOnly: enabled));

  /// 只看 / 不看已暂停的词条。
  void setSuspendedOnly({required bool enabled}) =>
      _apply(state.copyWith(suspendedOnly: enabled));

  /// 切换排序方式。
  void setSort(WordSort sort) => _apply(state.copyWith(sort: sort));

  /// 清除全部筛选并恢复默认排序（保留关键词）。
  ///
  /// 保留关键词是有意的：用户在窄屏筛选面板里点「清除筛选」，
  /// 期望的是「筛选条件没生效」，而不是把刚打上去的搜索词也抹掉。
  void clearFilters() => _apply(
    state.copyWith(
      clearMasteryLevel: true,
      clearInitializationStatus: true,
      wrongOnly: false,
      dueOnly: false,
      suspendedOnly: false,
      sort: WordSort.createdAt,
    ),
  );

  /// 清空**全部**查询条件，包括搜索词。
  ///
  /// 与 [clearFilters] 的分工是刻意的：窄屏筛选面板里的「清除筛选」只清
  /// 筛选条件、保留搜索词（用户在面板里输入的关键词不该被面板的另一个按钮
  /// 抹掉）。但「列表是空的、我不知道为什么空」需要的是**一键回到全部**，
  /// 那时候保留搜索词只会让用户点了按钮列表仍然是空的。
  ///
  /// 两个入口用不同的文案，才不会变成「同一个按钮有时清搜索有时不清」。
  void clearAll() => _apply(
    state.copyWith(
      search: '',
      clearMasteryLevel: true,
      clearInitializationStatus: true,
      wrongOnly: false,
      dueOnly: false,
      suspendedOnly: false,
      sort: WordSort.createdAt,
    ),
  );

  /// 触底或点击加载更多（每次追加一页 `wordListPageSize`）。
  void loadMore() {
    state = state.copyWith(limit: state.limit + wordListPageSize);
  }

  /// 翻到指定页（1 起）。
  void goToPage(int page) {
    if (page < 1) return;
    state = state.copyWith(offset: (page - 1) * state.limit);
  }

  /// 改完筛选条件后把偏移量与加载条数复位到首屏。
  void _apply(WordQuery next) =>
      state = next.copyWith(offset: 0, limit: wordListPageSize);
}

/// 查询条件提供者。
final NotifierProvider<WordQueryNotifier, WordQuery> wordQueryProvider =
    NotifierProvider<WordQueryNotifier, WordQuery>(WordQueryNotifier.new);

/// 当前页的词条列表。
final FutureProvider<List<WordListEntry>> wordListProvider =
    FutureProvider<List<WordListEntry>>((ref) {
      final query = ref.watch(wordQueryProvider);
      return ref.watch(wordDaoProvider).list(query);
    });

/// 符合当前筛选条件的词条总数。
final FutureProvider<int> wordCountProvider = FutureProvider<int>((ref) {
  final query = ref.watch(wordQueryProvider);
  return ref.watch(wordDaoProvider).count(query);
});

/// 按掌握等级的词条分布。
final FutureProvider<Map<MasteryLevel, int>> masterySummaryProvider =
    FutureProvider<Map<MasteryLevel, int>>(
      (ref) => ref.watch(wordDaoProvider).countByMastery(),
    );

/// 词库整体的掌握概览，供页首那条进度带使用。
class MasteryOverview {
  /// 以总数与已掌握数构造。
  const new({required this.total, required this.mastered});

  /// 词条总数。
  final int total;

  /// 已掌握的词条数。
  final int mastered;

  /// 还有多少个词条待继续学习。
  int get remaining => total - mastered < 0 ? 0 : total - mastered;

  /// 掌握百分比（0–100）。
  int get percent => total == 0 ? 0 : (mastered * percentScale / total).round();
}

/// 页首「掌握概览」的数值。
///
/// **与当前筛选无关**：概览回答的是「我这个词库学得怎么样」，
/// 跟着搜索词一起缩水会让进度条忽上忽下，读起来像数据出错。
///
/// **为什么不用 `DashboardOverview`**：那份概览由 `word_detail_dao.dart`
/// 提供，而掌握分布本来就有一条现成的聚合查询；多引一个跨模块依赖只会让
/// 两边算出两个口径不同的「已掌握」。这里的折算与旧版 `/api/dashboard`
/// 的 `masteredWords` 同口径：总数是各等级之和，已掌握取 `MASTERED`。
final FutureProvider<MasteryOverview> masteryOverviewProvider =
    FutureProvider<MasteryOverview>((ref) async {
      final summary = await ref.watch(masterySummaryProvider.future);
      return MasteryOverview(
        total: summary.values.fold(0, (sum, count) => sum + count),
        mastered: summary[MasteryLevel.mastered] ?? 0,
      );
    });
