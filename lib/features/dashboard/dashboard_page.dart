/// 首页「今日」。
///
/// 展示真实的每日学习概览：今日计划、学习统计、到期与错词提醒，以及双端
/// 平台能力。**这里不出现任何假数据**——旧版 `import/page.tsx` 写死
/// `value={75}` 的假进度条是明确的负面示范（见 CLEAN_CODE_BASELINE.md）。
///
/// 每张卡片都是独立组件、各自 `watch` 所需的数据提供者，因此页面本身
/// 不需要任何状态；旧版首页把 6 个 hook 的结果在页面里粘合再逐层下传，
/// 这里改为「卡片自取」。
///
/// **空库时整页换成导入引导**：一个还没有任何词条的用户，整页卡片
/// 全部显示 0，对「下一步做什么」零信息量。旧版 `page.tsx:72-87`
/// 在 `totalWords === 0` 时直接返回空状态，本版沿用同一个判据。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/features/dashboard/cards/platform_card.dart';
import 'package:lexiloop/features/dashboard/cards/practice_card.dart';
import 'package:lexiloop/features/dashboard/cards/reminders_card.dart';
import 'package:lexiloop/features/dashboard/cards/resume_session_card.dart';
import 'package:lexiloop/features/dashboard/cards/statistics_card.dart';
import 'package:lexiloop/features/dashboard/cards/suggestion_card.dart';
import 'package:lexiloop/features/dashboard/cards/today_plan_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 空库引导的标题 Key，供测试定位。
const Key emptyStateTitleKey = Key('dashboard-empty-title');

/// 空库引导的主按钮 Key，供测试定位。
const Key emptyStateImportButtonKey = Key('dashboard-empty-import');

/// 首页。
class DashboardPage extends ConsumerWidget {
  /// 创建首页。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(dashboardOverviewProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(child: _DashboardBody(overview: overview)),
    );
  }
}

/// 首页内容：空库时走导入引导，否则走正常卡片流。
///
/// **概览未加载时不显示空状态**：`totalWords` 在飞行途中是未知值，
/// 此刻宣布「你还没有词条」会让已入库的用户每次冷启动都看到一次误报。
class _DashboardBody extends StatelessWidget {
  const new({required this.overview});

  final AsyncValue<DashboardOverview> overview;

  @override
  Widget build(BuildContext context) => switch (overview) {
    AsyncData<DashboardOverview>(:final value) when value.totalWords == 0 =>
      const _EmptyLibraryState(),
    _ => const _DashboardCards(),
  };
}

/// 正常的卡片流。
///
/// 其中 [ResumeSessionCard] 只在存在可恢复会话时出现，其余六张常驻。
class _DashboardCards extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
    children: const <Widget>[
      _PageHeader(),
      // 「继续上次学习」挂在今日队列上方（对应旧版 `page.tsx:142-148` 的
      // 位置）：用户刚回首页时最想接上的就是那条做了一半的会话，
      // 排在今日计划之前才不会被 30 题的配额盖住。没有可恢复会话时
      // 它自己渲染成空，不占位置。
      ResumeSessionCard(),
      SizedBox(height: 10),
      TodayPlanCard(),
      SizedBox(height: 10),
      SuggestionCard(),
      SizedBox(height: 10),
      StatisticsCard(),
      SizedBox(height: 10),
      RemindersCard(),
      SizedBox(height: 10),
      PracticeCard(),
      SizedBox(height: 10),
      PlatformCapabilityCard(),
    ],
  );
}

/// 页面标题区。
class _PageHeader extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '今日',
          style: LexiType.display.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'LexiLoop 词环 · 纯本地',
          style: LexiType.callout.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

/// 空库引导：导入 EasyDict 收藏。
///
/// **保留页面标题**：用户是从「今日」这个 Tab 走进来的，把标题也一并撤掉
/// 会让导航高亮指向一个页面上根本没有出现过的名字；旧版整页替换的做法
/// 在有侧边栏的框架里反而制造了不一致。
class _EmptyLibraryState extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: <Widget>[
        const _PageHeader(),
        const SizedBox(height: 16),
        const Center(child: _EmptyIcon()),
        const SizedBox(height: 20),
        Text(
          '从 EasyDict 收藏开始',
          key: emptyStateTitleKey,
          textAlign: TextAlign.center,
          style: LexiType.title2.copyWith(
            color: colors.label,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '导入 EasyDict Favorites CSV。LexiLoop 只初始化你实际收藏的词条，不会导入整本词典。',
          textAlign: TextAlign.center,
          style: LexiType.body.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          key: emptyStateImportButtonKey,
          onPressed: () => context.go(csvImportPath),
          icon: const Icon(Icons.upload_file_rounded, size: 19),
          label: const Text('导入 CSV'),
        ),
      ],
    );
  }
}

/// 空库引导的渐变图标。
class _EmptyIcon extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      width: emptyIconSize,
      height: emptyIconSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LexiRadius.xl),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.accent, colors.purple],
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.menu_book_rounded,
        size: emptyIconGlyphSize,
        color: Colors.white,
      ),
    );
  }
}

/// CSV 导入页的路由。
///

/// 空库引导图标的边长。
const double emptyIconSize = 80;

/// 空库引导图标的字形尺寸。
const double emptyIconGlyphSize = 40;
