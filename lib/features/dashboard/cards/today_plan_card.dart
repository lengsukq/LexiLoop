/// 今日计划卡片。
///
/// 对应旧版首页的 hero + 「今日队列」：计划总题数、今日完成度进度条、
/// 到期复习 / 错词 / 新词三条队列，以及进入学习的入口。
///
/// **队列行是入口而不是只读统计**：旧版 `QueueCard` 带 `href`，
/// 本版一度把它们做成纯文本行，于是「错词强化」在首页只能看不能点，
/// 唯一的入口是学习页里的模式选择。本版按 query 深链回到对应模式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/dashboard/cards/dashboard_card.dart';
import 'package:lexiloop/features/dashboard/cards/resume_session_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 「开始学习」按钮的 Key，供测试定位。
const Key startStudyButtonKey = Key('dashboard-start-study');

/// 今日计划总题数的 Key，供测试定位。
const Key plannedTotalKey = Key('dashboard-planned-total');

/// 今日完成度文字（含百分比）的 Key，供测试定位。
const Key goalProgressKey = Key('dashboard-goal-progress');

/// 「今日目标已达成」徽章的 Key，供测试定位。
const Key goalReachedBadgeKey = Key('dashboard-goal-reached');

/// 今日计划卡片：到期复习 / 错词 / 新词的计划数与可用数、今日完成度。
class TodayPlanCard extends ConsumerWidget {
  /// 创建今日计划卡片。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(dailyPlanProvider);
    final overview = ref.watch(dashboardOverviewProvider);
    return SectionCard(
      tone: LexiTone.mint,
      variant: SurfaceVariant.hero,
      title: '今日计划',
      icon: LucideIcons.calendarDays,
      child: plan.when(
        loading: DashboardLoading.new,
        error: (error, _) => DashboardError(
          message: '学习计划加载失败：$error',
          onRetry: () => ref.invalidate(dailyPlanProvider),
        ),
        data: (value) => _PlanBody(
          plan: value,
          overview: switch (overview) {
            AsyncData<DashboardOverview>(:final value) => value,
            _ => null,
          },
        ),
      ),
    );
  }
}

class _PlanBody extends StatelessWidget {
  const new({required this.plan, required this.overview});

  final DailyStudyPlan plan;

  /// 概览；尚未加载或失败时为 `null`，此时不显示完成度而不是显示 0%。
  final DashboardOverview? overview;

  @override
  Widget build(BuildContext context) {
    final overview = this.overview;
    // 概览未到达时按「未达成」渲染：按钮文案与副标题都只在达成时换一套说法，
    // 宁可晚一拍也不要先闪一次「继续无限学习」。
    final reached = overview != null && _goalReached(overview);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const ResumeSessionCard(embedded: true),
        Row(
          children: <Widget>[
            Expanded(
              child: _PlannedHeadline(
                plan: plan,
                goalReached: reached,
                completedToday: overview?.completedToday ?? 0,
              ),
            ),
            if (overview != null) _GoalProgress(overview: overview),
          ],
        ),
        const SizedBox(height: LexiSpace.s8),
        if (reached) const _GoalReachedBadge(),
        _PlanQueues(plan: plan),
        const SizedBox(height: LexiSpace.s12),
        _StartStudyButton(goalReached: reached),
      ],
    );
  }
}

/// 计划总题数与预估耗时；目标达成后改用「已完成」话术。
class _PlannedHeadline extends StatelessWidget {
  const new({
    required this.plan,
    required this.goalReached,
    required this.completedToday,
  });

  final DailyStudyPlan plan;

  /// 今日目标是否已达成，决定右侧那句话用「预计」还是「已完成」。
  final bool goalReached;

  /// 今日已处理题数；仅在 [goalReached] 为真时被读到。
  final int completedToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: LexiSpace.s8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Text(
              '${plan.plannedTotal}',
              key: plannedTotalKey,
              style: LexiType.hero.copyWith(color: colors.label),
            ),
            Text(
              '题待完成',
              style: LexiType.body.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
        Text(
          goalReached
              ? '已处理 $completedToday 题，继续保持'
              : '预估 ${plan.estimatedMinutes} 分钟',
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
      ],
    );
  }
}

/// 今日完成度：进度条 + 达成徽章。
///
/// **目标为 0 时不显示达成徽章**：没有计划就没有目标，
/// 「0 >= 0」成立会让徽章在空库用户首页永远亮着。
class _GoalProgress extends StatelessWidget {
  const new({required this.overview});

  final DashboardOverview overview;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final reached = _goalReached(overview);

    return Column(
      children: <Widget>[
        SizedBox(
          width: _goalRingSize,
          height: _goalRingSize,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned.fill(
                child: CircularProgressIndicator(
                  value: _progressValue(overview).clamp(0, 1),
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: colors.fill,
                ),
              ),
              Icon(
                reached ? LucideIcons.check : LucideIcons.flag,
                size: 20,
                color: colors.accentText,
              ),
            ],
          ),
        ),
        const SizedBox(height: LexiSpace.s6),
        Text(
          _progressLabel(overview),
          key: goalProgressKey,
          style: LexiType.caption.copyWith(color: colors.secondaryLabel),
        ),
      ],
    );
  }
}

/// 「今日目标已达成」徽章。
class _GoalReachedBadge extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const LexiBadge(
    key: goalReachedBadgeKey,
    label: '今日目标已达成',
    tone: LexiBadgeTone.success,
  );
}

/// 三条可跳转的队列行 + 只读的句子复习行。
class _PlanQueues extends StatelessWidget {
  const new({required this.plan});

  final DailyStudyPlan plan;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: LexiSpace.s4,
      runSpacing: LexiSpace.s4,
      children: <Widget>[
        _QueueRow(
          mode: StudyMode.dueReview,
          label: '复习',
          value: '${plan.plannedDueReviewCount}',
          note: '${plan.dueReviewCount} 可用',
          valueKey: const Key('dashboard-due-review'),
        ),
        _QueueRow(
          mode: StudyMode.wrongWords,
          label: '错词',
          value: '${plan.plannedWrongWordCount}',
          note: '${plan.wrongWordCount} 可用',
          valueKey: const Key('dashboard-wrong-words'),
        ),
        _QueueRow(
          mode: StudyMode.newWords,
          label: '新词',
          value: '${plan.plannedNewWordCount}',
          note: '${plan.newWordCount} 可用',
          valueKey: const Key('dashboard-new-words'),
        ),
        _QueueRow(
          mode: StudyMode.sentenceReview,
          label: '句子',
          value: '${plan.plannedSentenceReviewCount}',
          note: '${plan.sentenceReviewCount} 可用',
          valueKey: const Key('dashboard-sentences'),
        ),
      ],
    );
  }
}

/// 可点击的队列行：点击进入该模式的会话。
class _QueueRow extends StatelessWidget {
  const new({
    required this.mode,
    required this.label,
    required this.value,
    required this.note,
    required this.valueKey,
  });

  final StudyMode mode;
  final String label;
  final String value;
  final String note;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    // 行看起来仍像统计数字，tooltip 负责说明「点了会去哪儿」，
    // 桌面端悬停与读屏都能得到这条信息。
    return Tooltip(
      message: '开始${studyModeLabel(mode)} · $note',
      child: TextButton(
        onPressed: () => goToStudyMode(context, mode),
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s6),
          backgroundColor: context.lexiColors.card,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: LexiType.caption),
            const SizedBox(width: LexiSpace.s4),
            Text(value, key: valueKey, style: LexiType.caption),
          ],
        ),
      ),
    );
  }
}

/// 「开始学习」入口。
///
/// **目标达成后换成「继续无限学习」**：沿用旧版 hero 的说法，让用户一眼看出
/// 「今天已经做完了，接下来是自愿加练」。这里只换文案——无限学习本身是
/// 后续阶段的能力，按钮的行为仍是进入每日综合模式。
class _StartStudyButton extends ConsumerWidget {
  const new({required this.goalReached});

  final bool goalReached;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = switch (ref.watch(resumableSessionProvider)) {
      AsyncData<ResumableSession?>(:final value) => value,
      _ => null,
    };
    // **不再铺满整行**。目标为 0 时它是一个 1040 像素宽、通体蓝色、
    // 上面只有四个字的条——首页最重的视觉元素落在一个主次不明的横条上。
    // 按内容取宽、左对齐，让它读起来像一个按钮而不是一条横幅。
    // 窄屏（< 480）时仍然铺满：那里每个像素都要用上，拇指也更好按。
    final narrow = MediaQuery.sizeOf(context).width < compactHeaderWidth;
    final button = FilledButton.icon(
      key: startStudyButtonKey,
      onPressed: () => session == null
          ? goToDestination(context, studyDestinationLabel)
          : goToStudyMode(context, session.mode),
      icon: const Icon(LucideIcons.play, size: 19),
      label: Text(
        session != null
            ? '继续学习'
            : goalReached
            ? '继续无限学习'
            : '开始学习',
      ),
    );
    if (narrow) {
      return SizedBox(width: double.infinity, child: button);
    }
    return Align(alignment: Alignment.centerLeft, child: button);
  }
}

/// 今日目标是否已达成。
///
/// **目标为 0 时不算达成**：没有计划就没有目标，「0 >= 0」会让徽章与
/// 「继续无限学习」在空库用户的首页永远亮着。
bool _goalReached(DashboardOverview overview) =>
    overview.todayGoalTotal > 0 &&
    overview.completedToday >= overview.todayGoalTotal;

/// 完成度百分比文案。
///
/// 目标为 0 时给 `0%`：空进度条配「100%」是自相矛盾的展示。
String _progressLabel(DashboardOverview overview) {
  final total = overview.todayGoalTotal;
  final percent = total == 0
      ? 0
      : (overview.completedToday * 100 / total).round();
  return '${overview.completedToday}/$total ($percent%)';
}

/// 进度条取值，上限 1（超额完成时不应画到两倍宽）。
double _progressValue(DashboardOverview overview) {
  final total = overview.todayGoalTotal;
  if (total == 0) return 0;
  return overview.completedToday / total;
}

const double _goalRingSize = 48;
