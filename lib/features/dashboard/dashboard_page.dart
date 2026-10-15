/// 首页「今日」。
///
/// 展示真实的每日学习概览：今日计划、学习统计、到期与错词提醒，以及双端
/// 平台能力。**这里不出现任何假数据**——旧版 `import/page.tsx` 写死
/// `value={75}` 的假进度条是明确的负面示范（见 CLEAN_CODE_BASELINE.md）。
///
/// 每张卡片都是独立组件、各自 `watch` 所需的数据提供者，因此页面本身
/// 不需要任何状态；旧版首页把 6 个 hook 的结果在页面里粘合再逐层下传，
/// 这里改为「卡片自取」。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/features/dashboard/cards/platform_card.dart';
import 'package:lexiloop/features/dashboard/cards/reminders_card.dart';
import 'package:lexiloop/features/dashboard/cards/statistics_card.dart';
import 'package:lexiloop/features/dashboard/cards/today_plan_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 首页。
class DashboardPage extends StatelessWidget {
  /// 创建首页。
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: <Widget>[
            Text(
              '今日',
              style: TextStyle(
                color: colors.label,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'LexiLoop 词环 · 纯本地',
              style: TextStyle(color: colors.secondaryLabel, fontSize: 14),
            ),
            const SizedBox(height: 20),
            const TodayPlanCard(),
            const SizedBox(height: 10),
            const StatisticsCard(),
            const SizedBox(height: 10),
            const RemindersCard(),
            const SizedBox(height: 10),
            const PlatformCapabilityCard(),
          ],
        ),
      ),
    );
  }
}
