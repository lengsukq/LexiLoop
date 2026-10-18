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
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/mastery_distribution_card.dart';
import 'package:lexiloop/features/statistics/widgets/overview_cards.dart';
import 'package:lexiloop/features/statistics/widgets/question_type_card.dart';
import 'package:lexiloop/features/statistics/widgets/recent_daily_detail_card.dart';
import 'package:lexiloop/features/statistics/widgets/recent_results_card.dart';
import 'package:lexiloop/features/statistics/widgets/trend_chart_card.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/widgets/adaptive_columns.dart';
import 'package:lexiloop/ui/widgets/disclosure_section.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 统计页。
class StatisticsPage extends ConsumerWidget {
  /// 以键构造。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PageShell(
      scrollable: true,
      header: PageHeader(
        title: '学习统计',
        subtitle: '近一月的作答量、正确率、掌握度分布与每日明细。',
        actions: <PageHeaderAction>[
          PageHeaderAction(
            key: const Key('statistics-refresh'),
            label: '刷新',
            icon: LucideIcons.refreshCw,
            onPressed: () => refreshStatistics(ref),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OverviewCards(),
          SizedBox(height: LexiLayout.sectionGap),
          TrendChartCard(),
          SizedBox(height: LexiLayout.sectionGap),
          AdaptiveColumns(
            primary: MasteryDistributionCard(),
            secondary: QuestionTypeCard(),
            secondaryWidth: 360,
          ),
          SizedBox(height: LexiLayout.sectionGap),
          DisclosureSection(
            title: '近期作答与每日明细',
            child: Column(
              children: <Widget>[
                RecentResultsCard(),
                SizedBox(height: LexiLayout.cardGap),
                RecentDailyDetailCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
