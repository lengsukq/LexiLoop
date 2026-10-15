/// 本地数据被整体替换后的缓存失效清单。
///
/// **为什么需要这张清单**：备份导入与「清空全部数据」都是**原地替换**
/// 同一个 SQLite 文件里的内容，而 `AppDatabase` 实例不变。于是所有已经
/// 算出来的 `FutureProvider` 结果都变成了过期快照——用户导入备份后回到首页
/// 看到的还是导入前的词条数与正确率。
///
/// Riverpod 没有「一键失效全部」的 API（`databaseProvider` 不能失效：
/// 失效它会关掉连接并新建一个，与进行中的查询打架），所以这里显式列出
/// 所有**读取本地数据库**的 provider。
///
/// **维护约定**：新增一个会读库的顶层 provider 时，必须把它加进
/// [dataBackedProviders]，否则恢复备份后该页面会显示过期数据。
/// `test/features/settings/data_invalidation_test.dart` 会用行为测试覆盖
/// 这里最关键的几条路径。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/features/import/import_providers.dart';
import 'package:lexiloop/features/initialize/initialize_providers.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/study/study_providers.dart';
import 'package:lexiloop/features/word_detail/word_detail_providers.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/services/settings_service.dart';

/// 会因本地数据被整体替换而失效的 provider。
///
/// 刻意**不包含**两类：
/// - DAO 与服务（`wordDaoProvider` 等）：它们只是无状态构造器，不缓存查询结果；
/// - 纯界面状态（`wordQueryProvider`、`queueFilterProvider` 等）：它们描述
///   「用户在筛选什么」，恢复后继续沿用反而更自然。
final List<ProviderOrFamily> dataBackedProviders = <ProviderOrFamily>[
  appSettingsProvider,
  importHistoryProvider,
  importBatchRowsProvider,
  wordListProvider,
  wordCountProvider,
  masterySummaryProvider,
  dashboardOverviewProvider,
  dashboardNowProvider,
  dailySuggestionProvider,
  dailyPlanProvider,
  statisticsOverviewProvider,
  dailyTrendProvider,
  questionTypeAccuracyProvider,
  recentResultsProvider,
  wordDetailProvider,
  wordLearningSnapshotProvider,
  queuePageProvider,
  queueProgressProvider,
  studySessionProvider,
];

/// 失效 [dataBackedProviders] 中的全部 provider，并重载设置服务缓存。
///
/// 设置服务（`SettingsService`）单独处理：它内部缓存了设置表的内容，
/// 恢复备份后必须连同它的缓存一起丢掉。
///
/// 接收 [WidgetRef] 而非 `Ref`：Riverpod 只导出了 `WidgetRef` 这一个
/// 面向界面的引用类型，而「恢复备份」本来就只能是界面上的一个动作。
/// 需要在 widget 之外调用时（例如测试），用 [invalidateDataBackedProviders]。
void invalidateLocalData(WidgetRef ref) {
  invalidateDataBackedProviders(
    invalidate: ref.invalidate,
    settings: ref.read(settingsServiceProvider),
  );
}

/// [invalidateLocalData] 的底层实现。
///
/// 把「失效什么」与「怎么失效」拆开，才能在 widget 之外直接调用：
/// `WidgetRef` 只能从 `build` 里取到，测试拿不到。
void invalidateDataBackedProviders({
  required void Function(ProviderOrFamily) invalidate,
  required SettingsService settings,
}) {
  settings.invalidate();
  dataBackedProviders.forEach(invalidate);
}
