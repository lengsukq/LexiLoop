/// 概览指标卡片组。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/stat_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 概览指标：词条数、累计作答、正确率、连续天数、累计时长。
class OverviewCards extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(statisticsOverviewProvider);
    return overview.when(
      data: (data) => data.totalWords == 0 && data.totalReviews == 0
          // **新用户不该看到一排 0**：六个格子全是 0 时，这一页唯一
          // 能得出的结论是「这里没东西可看」。给一句方向比给六个 0 有用。
          ? const StatCard(
              title: '概览',
              child: EmptyHint(message: '还没有学习记录。先去「单词本」加几个词，或从「今日」开始一轮复习。'),
            )
          : Surface(
              borderRadius: BorderRadius.circular(LexiRadius.lg),
              padding: const EdgeInsets.all(cardPadding),
              child: Wrap(
                spacing: metricColumnGap,
                runSpacing: metricRowGap,
                children: <Widget>[
                  _Metric(
                    label: '词条总数',
                    value: '${data.totalWords}',
                    width: metricWidth,
                  ),
                  _Metric(
                    label: '累计作答',
                    value: '${data.totalReviews}',
                    width: metricWidth,
                  ),
                  _Metric(
                    label: '正确率',
                    value: formatPercent(data.accuracy),
                    unit: '%',
                    color: context.lexiColors.success,
                    width: metricWidth,
                  ),
                  _Metric(
                    label: '连续学习',
                    value: '${data.streakDays}',
                    unit: '天',
                    color: context.lexiColors.warning,
                    width: metricWidth,
                  ),
                  _Metric(
                    label: '累计时长',
                    value: formatDuration(data.totalDurationMs),
                    width: metricWidthWide,
                  ),
                  _Metric(
                    label: '学习天数',
                    value: '${data.activeDays}',
                    unit: '天',
                    width: metricWidth,
                  ),
                ],
              ),
            ),
      loading: () => const StatCard(
        title: '概览',
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => StatCard(
        title: '概览',
        child: Text(
          '加载失败：$error',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.lexiColors.danger),
        ),
      ),
    );
  }
}

/// 固定宽度的指标，使 `Wrap` 能整齐换行。
class _Metric extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.width,
    this.unit,
    this.color,
  });

  final String label;
  final String value;
  final double width;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: StatMetric(label: label, value: value, unit: unit, color: color),
  );
}

/// 指标格宽度。
const double metricWidth = 96;

/// 宽指标格宽度（用于「累计时长」这类较长文本）。
///
/// 168 是「4 小时 13 分钟」在 17pt 字号下不折行的宽度。
const double metricWidthWide = 168;

/// 指标之间的水平间距。
const double metricColumnGap = 12;

/// 指标之间的垂直间距。
const double metricRowGap = 16;
