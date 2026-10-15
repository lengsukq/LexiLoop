/// 错词与到期提醒卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 错词与到期提醒卡片：到期数、错词数，各带一个跳转按钮。
///
/// 两个按钮都只跳 `/words`：单词本页的筛选状态由 `wordQueryProvider` 持有，
/// 而 `WordQuery` 目前只支持掌握等级与初始化状态两个维度，没有「错词」
/// 维度，因此带参跳转无法落地（详见交付说明）。
class RemindersCard extends ConsumerWidget {
  /// 创建提醒卡片。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(dashboardOverviewProvider);
    return SectionCard(
      title: '提醒',
      icon: Icons.notifications_none_rounded,
      child: overview.when(
        loading: DashboardLoading.new,
        error: (error, _) => DashboardError(
          message: '提醒加载失败：$error',
          onRetry: () => ref.invalidate(dashboardOverviewProvider),
        ),
        data: (value) => _RemindersBody(overview: value),
      ),
    );
  }
}

class _RemindersBody extends StatelessWidget {
  const new({required this.overview});

  final DashboardOverview overview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReminderRow(
          id: 'due',
          label: '今日到期',
          count: overview.dueToday,
          actionLabel: '去复习',
        ),
        const SizedBox(height: 8),
        _ReminderRow(
          id: 'wrong',
          label: '错词本',
          count: overview.wrongWords,
          actionLabel: '查看错词',
        ),
      ],
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const new({
    required this.id,
    required this.label,
    required this.count,
    required this.actionLabel,
  });

  final String id;
  final String label;
  final int count;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: LexiType.body.copyWith(color: colors.secondaryLabel),
              ),
              Text(
                '$count',
                key: Key('dashboard-$id-count'),
                style: LexiType.title2.copyWith(
                  color: count == 0 ? colors.tertiaryLabel : colors.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () => goToDestination(context, '单词本'),
          child: Text(actionLabel),
        ),
      ],
    );
  }
}
