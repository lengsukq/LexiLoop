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
