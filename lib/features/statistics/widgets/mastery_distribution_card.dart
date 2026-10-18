/// 掌握等级分布卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/stat_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 掌握等级分布（横向占比条 + 计数）。
class MasteryDistributionCard extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(statisticsOverviewProvider);
    return StatCard(
      title: '掌握程度',
      child: overview.when(
        data: (data) => _Bars(byMastery: data.byMastery),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Text(
          '加载失败：$error',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: context.lexiColors.dangerText),
        ),
      ),
    );
  }
}

/// 各等级一行。
class _Bars extends StatelessWidget {
  const new({required this.byMastery});

  final Map<MasteryLevel, int> byMastery;

  @override
  Widget build(BuildContext context) {
    final total = byMastery.values.fold<int>(0, (sum, count) => sum + count);
    if (total == 0) {
      return const EmptyHint(message: '还没有词条');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final level in masteryDisplayOrder)
          Padding(
            padding: const EdgeInsets.only(bottom: rowGap),
            child: _Row(
              level: level,
              count: byMastery[level] ?? 0,
              total: total,
            ),
          ),
      ],
    );
  }
}

/// 单个等级的占比条与计数。
class _Row extends StatelessWidget {
  const new({required this.level, required this.count, required this.total});

  final MasteryLevel level;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                masteryLabel(level),
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colors.secondaryLabel),
              ),
            ),
            Text(
              '$count',
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.label),
            ),
          ],
        ),
        const SizedBox(height: labelGap),
        ProportionBar(
          ratio: total == 0 ? 0 : count / total,
          color: masteryColor(level, colors),
        ),
      ],
    );
  }
}

/// 掌握等级的中文名。
String masteryLabel(MasteryLevel level) => switch (level) {
  MasteryLevel.newWord => '未学',
  MasteryLevel.learning => '学习中',
  MasteryLevel.familiar => '熟悉',
  MasteryLevel.proficient => '熟练',
  MasteryLevel.mastered => '已掌握',
};

/// 掌握等级对应的颜色。
Color masteryColor(MasteryLevel level, LexiColors colors) => switch (level) {
  MasteryLevel.newWord => colors.quaternaryLabel,
  MasteryLevel.learning => colors.danger,
  MasteryLevel.familiar => colors.warning,
  MasteryLevel.proficient => colors.accent,
  MasteryLevel.mastered => colors.success,
};

/// 行间距。
const double rowGap = 12;

/// 标签与条的间距。
const double labelGap = 5;
