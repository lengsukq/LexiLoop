/// 复习趋势折线图。
///
/// 两条线：作答次数与答对次数。**不做双 Y 轴**——两者的量纲相同，
/// 同轴对比才能一眼看出正确率的变化，双轴反而会制造虚假的相关性。
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/stat_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 趋势折线图卡片。
class TrendChartCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trend = ref.watch(dailyTrendProvider);
    final selected = ref.watch(trendRangeProvider);
    return StatCard(
      // 标题由「每日作答」改成「复习趋势」，并接管原本在卡片外面那行
      // 「复习趋势 + 档位切换」：一个图表套两层标题（外层「复习趋势」、
      // 卡片内「每日作答」）说的几乎是同一件事，而档位只作用于这张图，
      // 放进卡片右上角才对得上它的作用范围。
      title: '复习趋势',
      trailing: TrendRangeSelector(
        selected: selected,
        onSelect: (days) => ref.read(trendRangeProvider.notifier).select(days),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // **两条线必须有图例**：收敛前图上有「作答」与「正确」两条曲线，
          // 却没有任何说明它们各自是什么颜色。同轴对比是这个卡片的核心
          // 主张（见文件头注释），而读者得先知道哪条是哪条。
          const _Legend(),
          const SizedBox(height: legendGap),
          // **没有数据时不要留 200 像素的空框**：固定高度是给折线用的，
          // 空态只需要一行字。此前空态被顶在一张 200 高的卡片最上面，
          // 下面是一片空白。
          SizedBox(
            height: _hasData(trend) ? chartHeight : null,
            child: trend.when(
              data: (data) => _Chart(stats: data),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Text(
                  '加载失败：$error',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: context.lexiColors.dangerText),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 当前区间是否有任何作答。
bool _hasData(AsyncValue<List<DailyReviewStat>> trend) => trend.maybeWhen(
  data: (days) => days.any((day) => day.reviewed > 0),
  orElse: () => true,
);

/// 折线图主体。
class _Chart extends StatelessWidget {
  const new({required this.stats});

  final List<DailyReviewStat> stats;

  @override
  Widget build(BuildContext context) {
    final total = stats.fold<int>(0, (sum, item) => sum + item.reviewed);
    if (total == 0) {
      return const EmptyHint(message: '这段时间还没有复习记录');
    }

    final maxY = stats
        .map((item) => item.reviewed)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return LineChart(_chartData(context, maxY));
  }

  /// 图表的全部几何与标注。
  ///
  /// 从 [build] 里拆出来是因为守卫对 `build()` 有 80 行上限——而这张图
  /// 的配置项（四条轴、网格、读数提示、两条曲线）本身就占了大半屏。
  LineChartData _chartData(BuildContext context, double maxY) {
    final colors = context.lexiColors;
    final interval = maxY == 0 ? 1.0 : maxY / gridLines;
    return LineChartData(
      minX: 0,
      maxX: (stats.length - 1).toDouble(),
      minY: 0,
      maxY: maxY == 0 ? 1 : maxY * axisHeadroom,
      // 打开点击读数：图上只有两条线时，读者最想知道的正是某个具体日子
      // 的数值；没有读数就只能靠网格线估。
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => <LineTooltipItem?>[
            for (final spot in spots)
              LineTooltipItem(
                '${_seriesLabel(spot.barIndex)} ${spot.y.round()}',
                TextStyle(color: spot.bar.color, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
      gridData: FlGridData(
        drawVerticalLine: false,
        horizontalInterval: interval,
        getDrawingHorizontalLine: (_) =>
            FlLine(color: colors.borderSubtle, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: _titles(context, interval),
      lineBarsData: _series(colors),
    );
  }

  /// 两条曲线：作答（带填充）与答对。
  List<LineChartBarData> _series(LexiColors colors) => <LineChartBarData>[
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
  ];

  /// 左侧数值刻度与底部日期刻度。
  FlTitlesData _titles(BuildContext context, double interval) {
    final colors = context.lexiColors;
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          reservedSize: leftTitleSize,
          interval: interval,
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
    dashArray: fill ? null : <int>[6, 4],
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

/// 读数提示里的序列名。
String _seriesLabel(int barIndex) =>
    barIndex == 0 ? trendReviewedLabel : trendCorrectLabel;

/// 图例：作答 / 正确。
class _Legend extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Wrap(
      spacing: LexiSpace.s16,
      runSpacing: LexiSpace.s4,
      children: <Widget>[
        _LegendEntry(color: colors.accent, label: trendReviewedLabel),
        _LegendEntry(
          color: colors.success,
          label: trendCorrectLabel,
          dashed: true,
        ),
      ],
    );
  }
}

/// 图例里的一项：实线/虚线 + 文案。
class _LegendEntry extends StatelessWidget {
  const new({required this.color, required this.label, this.dashed = false});

  final bool dashed;

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ExcludeSemantics(
          child: SizedBox(
            width: LexiSpace.s24,
            child: Row(
              children: <Widget>[
                for (var part = 0; part < (dashed ? 3 : 1); part++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: dashed ? LexiSpace.s2 : 0,
                      ),
                      child: ColoredBox(
                        color: color,
                        child: const SizedBox(height: LexiSpace.s2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: LexiSpace.s6),
        Text(
          label,
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
      ],
    );
  }
}

/// 图例文案：作答条。
const String trendReviewedLabel = '作答';

/// 图例文案：正确条。
const String trendCorrectLabel = '正确';

/// 图例与图表之间的间距。
const double legendGap = LexiSpace.s10;

/// 天数档位选择器。
class TrendRangeSelector extends StatelessWidget {
  /// 以当前档位与回调构造。
  const new({required this.selected, required this.onSelect, super.key});

  /// 当前选中的天数档位。
  final int selected;

  /// 选中某一档时的回调。
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Wrap(
      runSpacing: LexiSpace.s8,
      children: <Widget>[
        for (final days in trendDayOptions)
          Padding(
            padding: const EdgeInsets.only(left: chipGap),
            // **`InkWell` + `Semantics(selected:)`，不是 `GestureDetector`**：
            // 档位是一组单选控件，`GestureDetector` 没有涟漪、不进焦点遍历、
            // 也不会向读屏播报「第 2 项，共 4 项，已选中」。同样一组控件在
            // 设置页用的是 `SegmentedButton`（有完整语义），两处的可访问性
            // 不该因为实现方式不同而不一致。
            child: Semantics(
              button: true,
              selected: days == selected,
              label: trendRangeLabel(days),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: Key('statistics-range-$days'),
                  borderRadius: BorderRadius.circular(LexiRadius.sm),
                  onTap: () => onSelect(days),
                  child: Surface(
                    borderRadius: BorderRadius.circular(LexiRadius.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: chipPaddingH,
                      vertical: chipPaddingV,
                    ),
                    child: Text(
                      trendRangeLabel(days),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: days == selected
                            ? colors.accent
                            : colors.secondaryLabel,
                        fontWeight: days == selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 档位的展示文案。
///
/// 365 天写「一年」而不是「365 天」——与旧版 `statistics/page.tsx:40` 的
/// `Segmented` 选项逐字对齐：这一档描述的是「一年」这个时间尺度，
/// 写成精确天数反而与旁边三档的语感不一致。
String trendRangeLabel(int days) => days == trendYearDays ? '一年' : '$days 天';

/// 「一年」档位的天数，与 [trendDayOptions] 的最后一档一致。
const int trendYearDays = 365;

/// 标题与内容之间的间距。
const double itemGap = 10;

/// 档位按钮之间的间距。
const double chipGap = 6;

/// 档位按钮的水平内边距。
const double chipPaddingH = 10;

/// 档位按钮的垂直内边距。
const double chipPaddingV = 5;
