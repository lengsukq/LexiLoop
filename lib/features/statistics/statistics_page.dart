/// 统计页。
///
/// 对应旧版 `app/(main)/statistics/page.tsx`。
///
/// **拆分原则**：旧版这一页把所有图表与卡片塞在一个组件里。这里每张卡片
/// 一个文件，页面本身只负责取数与排版——`build()` 因此保持在 80 行以内。
///
/// **与旧版的有意差异**：旧版把「档位 Segmented + 刷新按钮」一起放在
/// `PageHeader` 的 action 区；本页没有 `PageHeader` 组件，标题行只放页面级的
/// 「刷新」（它刷新的是整页数据），档位留在「复习趋势」标题旁——档位影响的是
/// 趋势与明细两块，放在它们上方比放页头更容易看出作用范围。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/mastery_distribution_card.dart';
import 'package:lexiloop/features/statistics/widgets/overview_cards.dart';
import 'package:lexiloop/features/statistics/widgets/question_type_card.dart';
import 'package:lexiloop/features/statistics/widgets/recent_daily_detail_card.dart';
import 'package:lexiloop/features/statistics/widgets/recent_results_card.dart';
import 'package:lexiloop/features/statistics/widgets/trend_chart_card.dart';
import 'package:lexiloop/ui/glass.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 统计页。
class StatisticsPage extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AmbientBackground(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            pagePadding,
            pagePadding,
            pagePadding,
            pagePaddingBottom,
          ),
          children: <Widget>[
            _PageHeader(onRefresh: () => refreshStatistics(ref)),
            const SizedBox(height: sectionGap),
            const OverviewCards(),
            const SizedBox(height: sectionGap),
            const _TrendSection(),
            const SizedBox(height: sectionGap),
            const MasteryDistributionCard(),
            const SizedBox(height: sectionGap),
            const QuestionTypeCard(),
            const SizedBox(height: sectionGap),
            const RecentResultsCard(),
            const SizedBox(height: sectionGap),
            const RecentDailyDetailCard(),
          ],
        ),
      ),
    );
  }
}

/// 页头：标题 + 「刷新」。
class _PageHeader extends StatelessWidget {
  const new({required this.onRefresh});

  /// 点击「刷新」时重新拉取本页数据。
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            '学习统计',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(color: colors.label),
          ),
        ),
        OutlinedButton.icon(
          key: const Key('statistics-refresh'),
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: refreshIconSize),
          label: const Text('刷新'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.secondaryLabel,
            side: BorderSide(color: colors.borderDefault),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

/// 趋势图 + 档位切换。
class _TrendSection extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(trendRangeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '复习趋势',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: context.lexiColors.label),
              ),
            ),
            _RangeSelector(
              selected: selected,
              onSelect: (days) =>
                  ref.read(trendRangeProvider.notifier).select(days),
            ),
          ],
        ),
        const SizedBox(height: itemGap),
        const TrendChartCard(),
      ],
    );
  }
}

/// 天数档位选择器。
class _RangeSelector extends StatelessWidget {
  const new({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final days in trendDayOptions)
          Padding(
            padding: const EdgeInsets.only(left: chipGap),
            child: GestureDetector(
              key: Key('statistics-range-$days'),
              onTap: () => onSelect(days),
              child: LiquidGlass(
                level: GlassLevel.subtle,
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

/// 页面内边距。
const double pagePadding = 20;

/// 底部留白，避免最后一张卡片贴住导航。
const double pagePaddingBottom = 96;

/// 卡片之间的间距。
const double sectionGap = 16;

/// 标题与内容之间的间距。
const double itemGap = 10;

/// 档位按钮之间的间距。
const double chipGap = 6;

/// 档位按钮的水平内边距。
const double chipPaddingH = 10;

/// 档位按钮的垂直内边距。
const double chipPaddingV = 5;

/// 「刷新」按钮里图标的边长。
const double refreshIconSize = 16;
