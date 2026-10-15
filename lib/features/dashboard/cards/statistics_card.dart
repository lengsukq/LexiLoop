/// 学习统计卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';

/// 总词数的 Key，供测试定位。
const Key totalWordsKey = Key('dashboard-total-words');

/// 统计卡片：总词数、各掌握等级分布、今日已答、连续天数。
///
/// 分布用横向条形手绘，不引图表库：`fl_chart` 虽然已在依赖里，
/// 但五个等级的横向条形用 `FractionallySizedBox` 十几行就能表达，
/// 引一个图表库反而增加包体与主题对齐成本。
class StatisticsCard extends ConsumerWidget {
  /// 创建统计卡片。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(dashboardOverviewProvider);
    return DashboardCard(
      title: '学习统计',
      icon: Icons.bar_chart_rounded,
      child: overview.when(
        loading: DashboardLoading.new,
        error: (error, _) => DashboardError(
          message: '统计加载失败：$error',
          onRetry: () => ref.invalidate(dashboardOverviewProvider),
        ),
        data: (value) => _StatisticsBody(overview: value),
      ),
    );
  }
}

class _StatisticsBody extends StatelessWidget {
  const new({required this.overview});

  final DashboardOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              '${overview.totalWords}',
              key: totalWordsKey,
              style: TextStyle(
                color: colors.label,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '个词条',
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final level in MasteryLevel.values)
          _MasteryBar(
            level: level,
            count: overview.byMastery[level] ?? 0,
            total: overview.totalWords,
          ),
        const SizedBox(height: 12),
        DashboardStatRow(
          label: '今日已答',
          value: '${overview.reviewedToday}',
          note: ' 题',
          valueKey: const Key('dashboard-reviewed-today'),
        ),
        DashboardStatRow(
          label: '连续复习',
          value: '${overview.streakDays}',
          note: ' 天',
          valueKey: const Key('dashboard-streak-days'),
        ),
      ],
    );
  }
}

class _MasteryBar extends StatelessWidget {
  const new({required this.level, required this.count, required this.total});

  final MasteryLevel level;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(width: 76, child: MasteryBadge(level: level)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: 8,
                color: colors.fill,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: total == 0 ? 0 : count / total,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: colors.accent),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 34,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: colors.label,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
