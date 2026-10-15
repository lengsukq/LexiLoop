/// 复习趋势折线图。
///
/// 两条线：作答次数与答对次数。**不做双 Y 轴**——两者的量纲相同，
/// 同轴对比才能一眼看出正确率的变化，双轴反而会制造虚假的相关性。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/stat_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 趋势折线图卡片。
class TrendChartCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(dailyTrendProvider);
    return StatCard(
      title: '每日作答',
      child: SizedBox(
        height: chartHeight,
        child: trend.when(
          data: (data) => _Chart(stats: data),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text(
              '加载失败：$error',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.lexiColors.danger),
            ),
          ),
        ),
      ),
    );
  }
}

/// 折线图主体。
class _Chart extends StatelessWidget {
  const new({required this.stats});

  final List<DailyReviewStat> stats;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final total = stats.fold<int>(0, (sum, item) => sum + item.reviewed);
    if (total == 0) {
      return const EmptyHint(message: '这段时间还没有复习记录');
    }

    final maxY = stats
        .map((item) => item.reviewed)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (stats.length - 1).toDouble(),
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY * axisHeadroom,
        lineTouchData: const LineTouchData(enabled: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: maxY == 0 ? 1 : maxY / gridLines,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.borderSubtle, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              reservedSize: leftTitleSize,
              interval: maxY == 0 ? 1 : maxY / gridLines,
              getTitlesWidget: (value, meta) => Text(
                value.round().toString(),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: colors.tertiaryLabel),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              interval: labelInterval(stats.length),
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= stats.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: labelTopPadding),
                  child: Text(
                    shortDateKey(stats[index].dateKey),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colors.tertiaryLabel),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: <LineChartBarData>[
          _bar(
            stats.map((item) => item.reviewed.toDouble()).toList(),
            colors.accent,
            fill: true,
          ),
          _bar(
            stats.map((item) => item.correct.toDouble()).toList(),
            colors.success,
            fill: false,
          ),
        ],
      ),
    );
  }

  LineChartBarData _bar(
    List<double> values,
    Color color, {
    required bool fill,
  }) => LineChartBarData(
    spots: <FlSpot>[
      for (var index = 0; index < values.length; index += 1)
        FlSpot(index.toDouble(), values[index]),
    ],
    color: color,
    dotData: const FlDotData(show: false),
    belowBarData: BarAreaData(
      show: fill,
      color: color.withValues(alpha: fillAlpha),
    ),
  );
}

/// 图表高度。
const double chartHeight = 200;

/// Y 轴留白比例。
const double axisHeadroom = 1.2;

/// 水平网格线条数。
const double gridLines = 4;

/// 左侧刻度区宽度。
const double leftTitleSize = 32;

/// 底部标签上边距。
const double labelTopPadding = 4;

/// 填充透明度。
const double fillAlpha = 0.15;

/// 底部日期标签的间隔：最多显示 6 个。
double labelInterval(int count) =>
    count <= maxDateLabels ? 1 : count / maxDateLabels;

/// 底部最多显示的日期标签数。
const int maxDateLabels = 6;

/// 把 `2026-03-01` 缩短为 `3/1`。
String shortDateKey(String dateKey) {
  final parts = dateKey.split('-');
  if (parts.length < 3) return dateKey;
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (month == null || day == null) return dateKey;
  return '$month/$day';
}
