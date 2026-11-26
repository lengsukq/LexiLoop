/// 统计页的数据提供者。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';

/// 统计查询数据源。
final Provider<StatisticsDao> statisticsDaoProvider = Provider<StatisticsDao>(
  (ref) => StatisticsDao(ref.watch(databaseProvider)),
);

/// 趋势图当前选定的天数档位。
class TrendRangeNotifier extends Notifier<int> {
  @override
  int build() => defaultTrendDays;

  /// 切换档位（必须是 [trendDayOptions] 中的值）。
  void select(int days) {
    if (trendDayOptions.contains(days)) state = days;
  }
}

/// 趋势档位提供者。
final NotifierProvider<TrendRangeNotifier, int> trendRangeProvider =
    NotifierProvider<TrendRangeNotifier, int>(TrendRangeNotifier.new);

/// 逐日趋势。
final FutureProvider<List<DailyReviewStat>> dailyTrendProvider =
    FutureProvider<List<DailyReviewStat>>((ref) {
      final days = ref.watch(trendRangeProvider);
      return ref
          .watch(statisticsDaoProvider)
          .dailyTrend(now: DateTime.now().millisecondsSinceEpoch, days: days);
    });

/// 全局概览。
final FutureProvider<StatisticsOverview> statisticsOverviewProvider =
    FutureProvider<StatisticsOverview>(
      (ref) => ref
          .watch(statisticsDaoProvider)
          .overview(DateTime.now().millisecondsSinceEpoch),
    );

/// 各题型正确率。
final FutureProvider<List<QuestionTypeAccuracy>> questionTypeAccuracyProvider =
    FutureProvider<List<QuestionTypeAccuracy>>(
      (ref) => ref.watch(statisticsDaoProvider).accuracyByQuestionType(),
    );

/// 最近作答的正误序列。
final FutureProvider<List<bool>> recentResultsProvider =
    FutureProvider<List<bool>>(
      (ref) => ref
          .watch(statisticsDaoProvider)
          .recentResults(limit: recentResultsLimit),
    );

/// 掌握等级的展示顺序（从生到熟）。
const List<MasteryLevel> masteryDisplayOrder = <MasteryLevel>[
  MasteryLevel.newWord,
  MasteryLevel.learning,
  MasteryLevel.familiar,
  MasteryLevel.proficient,
  MasteryLevel.mastered,
];

/// 重新拉取统计页的全部数据。
///
/// 对应旧版 `app/(main)/statistics/page.tsx:40` 页头 action 区里的「刷新」按钮
/// （`Button variant="outline" onClick={() => void load()}`）：旧版重发一次
/// `/api/statistics` 请求，本版没有请求可发，改为让四个数据源 provider 失效重算。
///
/// **用 `invalidate` 而不是 `ref.refresh`**：刷新按钮不该把界面卡在「等新数据」
/// 上——各卡片自己的加载态已经能表达「正在重算」，而 `refresh` 会让整页
/// 先变空再填回来。
///
/// **维护约定**：新增统计页数据源时必须加进这里，否则刷新按钮会漏掉它。
/// `features/settings/data_invalidation.dart` 里另有一份同样的清单，那份管的是
/// 「备份恢复后」的失效；两者用途不同，刻意不共用（那个文件属设置页所有，
/// 统计页不该反向依赖它）。
void refreshStatistics(WidgetRef ref) {
  ref
    ..invalidate(statisticsOverviewProvider)
    ..invalidate(dailyTrendProvider)
    ..invalidate(questionTypeAccuracyProvider)
    ..invalidate(recentResultsProvider);
}
