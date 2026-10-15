/// 今日计划卡片。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 「开始学习」按钮的 Key，供测试定位。
const Key startStudyButtonKey = Key('dashboard-start-study');

/// 今日计划总题数的 Key，供测试定位。
const Key plannedTotalKey = Key('dashboard-planned-total');

/// 今日计划卡片：到期复习 / 错词 / 新词的计划数与可用数、预估耗时。
class TodayPlanCard extends ConsumerWidget {
  /// 创建今日计划卡片。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(dailyPlanProvider);
    return DashboardCard(
      title: '今日计划',
      icon: Icons.today_rounded,
      child: plan.when(
        loading: DashboardLoading.new,
        error: (error, _) => DashboardError(
          message: '学习计划加载失败：$error',
          onRetry: () => ref.invalidate(dailyPlanProvider),
        ),
        data: (value) => _PlanBody(plan: value),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const new({required this.plan});

  final DailyStudyPlan plan;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Text(
              '${plan.plannedTotal}',
              key: plannedTotalKey,
              style: TextStyle(
                color: colors.label,
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '题待完成',
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
            const Spacer(),
            Text(
              '预估 ${plan.estimatedMinutes} 分钟',
              style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DashboardStatRow(
          label: '到期复习',
          value: '${plan.plannedDueReviewCount}',
          note: ' / ${plan.dueReviewCount} 可用',
          valueKey: const Key('dashboard-due-review'),
        ),
        DashboardStatRow(
          label: '错词',
          value: '${plan.plannedWrongWordCount}',
          note: ' / ${plan.wrongWordCount} 可用',
          valueKey: const Key('dashboard-wrong-words'),
        ),
        DashboardStatRow(
          label: '新词',
          value: '${plan.plannedNewWordCount}',
          note: ' / ${plan.newWordCount} 可用',
          valueKey: const Key('dashboard-new-words'),
        ),
        DashboardStatRow(
          label: '句子复习',
          value: '${plan.plannedSentenceReviewCount}',
          note: ' / ${plan.sentenceReviewCount} 可用',
          valueKey: const Key('dashboard-sentences'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            key: startStudyButtonKey,
            onPressed: () => goToDestination(context, '复习'),
            icon: const Icon(Icons.play_arrow_rounded, size: 19),
            label: const Text('开始学习'),
          ),
        ),
      ],
    );
  }
}
