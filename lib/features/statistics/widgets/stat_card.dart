/// 统计页的公共卡片外壳与格式化工具。
///
/// 抽出来是为了让各卡片组件只关心「显示什么」，不重复写玻璃外壳与
/// 加载/错误态——旧版统计页在每个图表里各写了一遍骨架屏。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 统计卡片外壳。
class StatCard extends StatelessWidget {
  /// 以标题与内容构造。
  const new({
    required this.title,
    required this.child,
    this.trailing,
    super.key,
  });

  /// 卡片标题。
  final String title;

  /// 卡片内容。
  final Widget child;

  /// 标题右侧的附加内容。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      borderRadius: BorderRadius.circular(LexiRadius.lg),
      padding: const EdgeInsets.all(cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: colors.label),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: cardTitleGap),
          child,
        ],
      ),
    );
  }
}

/// 异步卡片的统一包装：加载中显示占位，出错显示中文提示。
class AsyncStatCard<T> extends ConsumerWidget {
  /// 以标题与数据源构造。
  const new({
    required this.title,
    required this.value,
    required this.builder,
    super.key,
  });

  /// 卡片标题。
  final String title;

  /// 数据源。
  final AsyncValue<T> value;

  /// 成功时的内容构造器。
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StatCard(
      title: title,
      child: value.when(
        data: (data) => builder(context, data),
        loading: () => const _CardPlaceholder(),
        error: (error, _) => Text(
          '加载失败：$error',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.lexiColors.danger),
        ),
      ),
    );
  }
}

/// 单个数字指标。
class StatMetric extends StatelessWidget {
  /// 以标签与数值构造。
  const new({
    required this.label,
    required this.value,
    this.unit,
    this.color,
    super.key,
  });

  /// 指标名称。
  final String label;

  /// 指标数值（已格式化）。
  final String value;

  /// 单位。
  final String? unit;

  /// 数值颜色；缺省用主强调色。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: colors.tertiaryLabel),
        ),
        const SizedBox(height: metricGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                value,
                // 允许折成两行：数值格是固定宽度的，「累计时长」这类
                // 「4 小时 13 分钟」在 132 宽里一行放不下，此前被截成
                // 「4 小时 13 …」——读者以为数据没算完。
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color ?? colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (unit != null)
              Padding(
                padding: const EdgeInsets.only(left: unitGap),
                child: Text(
                  unit!,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: colors.tertiaryLabel),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 横向占比条。
class ProportionBar extends StatelessWidget {
  /// 以比例与颜色构造。
  const new({required this.ratio, required this.color, super.key});

  /// 占比（0–1）。
  final double ratio;

  /// 条形颜色。
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(barRadius),
      child: Container(
        height: barHeight,
        color: colors.fill,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: ratio.clamp(0, 1),
          child: ColoredBox(color: color),
        ),
      ),
    );
  }
}

/// 把毫秒格式化为「X 小时 Y 分钟」或「Y 分钟」。
String formatDuration(int milliseconds) {
  final totalMinutes = milliseconds ~/ minuteMs;
  if (totalMinutes < statsMinutesPerHour) return '$totalMinutes 分钟';
  final hours = totalMinutes ~/ statsMinutesPerHour;
  final minutes = totalMinutes % statsMinutesPerHour;
  return minutes == 0 ? '$hours 小时' : '$hours 小时 $minutes 分钟';
}

/// 把比例格式化为百分数字符串（不含百分号）。
String formatPercent(double ratio) => (ratio * 100).round().toString();

/// 空数据提示。
class EmptyHint extends StatelessWidget {
  /// 以提示文案构造。
  const new({required this.message, super.key});

  /// 提示文案。
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: emptyHintPadding),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: context.lexiColors.tertiaryLabel),
      ),
    );
  }
}

/// 加载占位。
class _CardPlaceholder extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: placeholderPadding),
    child: Center(
      child: SizedBox(
        width: placeholderSize,
        height: placeholderSize,
        child: CircularProgressIndicator(
          strokeWidth: placeholderStroke,
          color: context.lexiColors.accent,
        ),
      ),
    ),
  );
}

/// 卡片内边距。
const double cardPadding = 16;

/// 卡片标题与内容的间距。
const double cardTitleGap = 12;

/// 指标标签与数值的间距。
const double metricGap = 2;

/// 数值与单位的间距。
const double unitGap = 3;

/// 占比条高度。
const double barHeight = 8;

/// 占比条圆角。
const double barRadius = LexiRadius.pill;

/// 空提示的垂直内边距。
const double emptyHintPadding = 8;

/// 占位指示器的尺寸。
const double placeholderSize = 20;

/// 占位指示器的线宽。
const double placeholderStroke = 2;

/// 占位区垂直内边距。
const double placeholderPadding = 12;
