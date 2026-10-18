/// 学习统计卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/status_badges.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 总词数的 Key，供测试定位。
const Key totalWordsKey = Key('dashboard-total-words');

/// 统计卡片：总词数、各掌握等级分布、今日已答（含今日正确率）、连续天数。
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
    return SectionCard(
      tone: LexiTone.sky,
      title: '学习统计',
      icon: LucideIcons.chartColumn,
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: _OverviewMetric(
                label: '词条',
                value: '${overview.totalWords}',
                valueKey: totalWordsKey,
              ),
            ),
            Expanded(
              child: _OverviewMetric(
                label: '今日已答',
                value: '${overview.reviewedToday}',
                valueKey: const Key('dashboard-reviewed-today'),
              ),
            ),
            Expanded(
              child: _OverviewMetric(
                label: '连续天数',
                value: '${overview.streakDays}',
                valueKey: const Key('dashboard-streak-days'),
              ),
            ),
          ],
        ),
        const SizedBox(height: LexiSpace.s8),
        Text(
          _reviewedNote(overview),
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
        DisclosureSection(
          title: '掌握分布',
          child: Column(
            children: <Widget>[
              for (final level in MasteryLevel.values)
                _MasteryBar(
                  level: level,
                  count: overview.byMastery[level] ?? 0,
                  total: overview.totalWords,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverviewMetric extends StatelessWidget {
  const new({required this.label, required this.value, required this.valueKey});
  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Text(
        value,
        key: valueKey,
        style: LexiType.title2.copyWith(color: context.lexiColors.label),
      ),
      const SizedBox(height: LexiSpace.s2),
      Text(
        label,
        style: LexiType.caption.copyWith(
          color: context.lexiColors.secondaryLabel,
        ),
      ),
    ],
  );
}

/// 「今日已答」一行右侧的补充说明。
///
/// **今天没作答时不说正确率**：[DashboardOverview.todayAccuracy] 在没有
/// 作答时是 `0` 而不是 `null`，直接渲染成「正确率 0%」会被读成
/// 「今天全错了」——事实是今天还没开始。这一分支改说「今日尚无作答」，
/// 与卡片上其余的 0 值（今日已答 0 题）读法一致。
String _reviewedNote(DashboardOverview overview) {
  if (overview.reviewedToday == 0) return ' 题 · 今日尚无作答';
  final percent = (overview.todayAccuracy * percentScale).round();
  return ' 题 · 正确率 $percent%';
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
      padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: _masteryLabelWidth,
            child: MasteryBadge(level: level),
          ),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(LexiRadius.pill),
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
          const SizedBox(width: LexiSpace.s8),
          SizedBox(
            width: _countColumnWidth,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: LexiType.body.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 掌握等级标签列宽——固定宽度让五行条形左端对齐。
const double _masteryLabelWidth = 76;

/// 计数列宽——右对齐的数值需要固定宽度才不会随位数抖动。
const double _countColumnWidth = 34;
