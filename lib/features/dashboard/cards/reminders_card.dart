/// 错词与到期提醒卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';

/// 错词与到期提醒卡片：到期数、错词数，各带一个跳转按钮。
///
/// **按钮要落到对应的筛选视图**，不能只跳 `/words`：卡片上写着「错词 12」，
/// 点「查看错词」却落在未筛选的完整词库上（12 个错词混在 3000 个词里），
/// 用户得自己去筛选栏再勾一次——这条路径之前是断的，理由写着「WordQuery
/// 没有错词维度」，但该维度（`wrongOnly` / `dueOnly`）其实一直都有。
///
/// 落地方式：先把 `wordQueryProvider` 设成目标筛选再跳转。筛选状态本来就
/// 是全局单例，词库页读的就是它——比在路由上带 query 参数再解析一遍简单，
/// 也不会出现「参数解析失败就静默落在未筛选状态」这种半坏不坏的情况。
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
        data: (value) => _RemindersBody(
          overview: value,
          onViewDue: () {
            ref.read(wordQueryProvider.notifier).setDueOnly(enabled: true);
            goToDestination(context, '单词本');
          },
          onViewWrong: () {
            ref.read(wordQueryProvider.notifier).setWrongOnly(enabled: true);
            goToDestination(context, '单词本');
          },
        ),
      ),
    );
  }
}

class _RemindersBody extends StatelessWidget {
  const new({
    required this.overview,
    required this.onViewDue,
    required this.onViewWrong,
  });

  final DashboardOverview overview;

  /// 跳到「只看今日到期」的单词本。
  final VoidCallback onViewDue;

  /// 跳到「只看活跃错词」的单词本。
  final VoidCallback onViewWrong;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ReminderRow(
          id: 'due',
          label: '今日到期',
          count: overview.dueToday,
          actionLabel: '查看到期',
          onView: onViewDue,
        ),
        const SizedBox(height: LexiSpace.s8),
        _ReminderRow(
          id: 'wrong',
          label: '错词本',
          count: overview.wrongWords,
          actionLabel: '查看错词',
          onView: onViewWrong,
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
    required this.onView,
  });

  final String id;
  final String label;
  final int count;
  final String actionLabel;

  /// 点击右侧按钮时的动作（设置筛选并跳转）。
  final VoidCallback onView;

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
        TextButton(onPressed: onView, child: Text(actionLabel)),
      ],
    );
  }
}
