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
import 'package:lexiloop/features/dashboard/cards/practice_card.dart';
import 'package:lexiloop/features/dashboard/cards/reminders_card.dart';
import 'package:lexiloop/features/dashboard/cards/statistics_card.dart';
import 'package:lexiloop/features/dashboard/cards/suggestion_card.dart';
import 'package:lexiloop/features/dashboard/cards/today_plan_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/lexi_reveal.dart';
import 'package:lexiloop/ui/widgets/page_header.dart';
import 'package:lexiloop/ui/widgets/page_shell.dart';
import 'package:lexiloop/ui/widgets/page_states.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
    return _DashboardBody(overview: overview);
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

/// 任务与概览构成首屏，练习和建议接在后方。
class _DashboardCards extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => PageShell(
    scrollable: true,
    header: const PageHeader(title: '今日', subtitle: '今天要复习的词、错词与新词，都从这里开始。'),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= LexiLayout.wideBreakpoint &&
            MediaQuery.textScalerOf(context).scale(14) < 24;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            LexiReveal(child: _DashboardTop(wide: wide)),
            const SizedBox(height: LexiSpace.s20),
            const LexiReveal(index: 1, child: PracticeCard()),
            const SizedBox(height: LexiSpace.s24),
            if (wide)
              const LexiReveal(
                index: 2,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: SuggestionCard()),
                    SizedBox(width: LexiSpace.s24),
                    Expanded(child: RemindersCard()),
                  ],
                ),
              )
            else ...<Widget>[
              const LexiReveal(index: 2, child: SuggestionCard()),
              const SizedBox(height: LexiSpace.s16),
              const LexiReveal(index: 3, child: RemindersCard()),
            ],
          ],
        );
      },
    ),
  );
}

class _DashboardTop extends StatelessWidget {
  const new({required this.wide});
  final bool wide;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          TodayPlanCard(),
          SizedBox(height: LexiSpace.s16),
          StatisticsCard(),
        ],
      );
    }
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(flex: 2, child: TodayPlanCard()),
        SizedBox(width: LexiSpace.s24),
        Expanded(child: StatisticsCard()),
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
  Widget build(BuildContext context) => PageShell(
    scrollable: true,
    header: const PageHeader(title: '今日', subtitle: '词库还是空的——先导入，再开始复习。'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PageEmptyState(
          key: emptyStateTitleKey,
          icon: LucideIcons.bookOpen,
          title: '从 EasyDict 收藏开始',
          message:
              '导入 EasyDict / 通用词表（CSV / TSV / TXT）、粘贴英文文章按考试难度智能分词， '
              '或直接下载内置四六级 / 雅思 / 托福词书包开背。',
          primaryLabel: '导入 CSV',
          primaryKey: emptyStateImportButtonKey,
          onPrimary: () => context.go(csvImportPath),
          secondaryLabel: '浏览词书包',
          secondaryKey: const Key('dashboard-empty-packs'),
          onSecondary: () => context.go(packsPath),
        ),
        const SizedBox(height: LexiSpace.s12),
        Center(
          child: TextButton.icon(
            key: const Key('dashboard-empty-article'),
            onPressed: () => context.go(articlePath),
            icon: const Icon(LucideIcons.fileText, size: 16),
            label: const Text('粘贴英文文章智能分词'),
          ),
        ),
      ],
    ),
  );
}
