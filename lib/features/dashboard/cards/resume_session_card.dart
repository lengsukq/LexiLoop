/// 「继续上次学习」卡片。
///
/// 对应旧版 `src/app/(main)/page.tsx:142-148`：今日队列上方的一条窄卡片，
/// 图标 + 「继续上次学习」+「{会话类型} · 还剩 N 题」+「继续 →」，
/// 点击回到该会话对应的学习模式。
///
/// **没有可恢复会话时整张卡片不渲染**：旧版用 `data.resumeSession && ...`
/// 整块条件渲染。空卡片会把用户引到一个无事可做的入口上——「继续上次学习」
/// 下面写着「还剩 0 题」是最典型的假入口。
///
/// **加载中同样不渲染**：数据未到达时先渲染一张空卡片、拿到结果再撤掉，
/// 会让首页在每次冷启动时闪一下这个入口。
///
/// **会话类型的中文名复用 [studyModeLabel]，不再抄一份旧版的 `sessionLabel`**：
/// 旧版 `page.tsx:305-307` 自带一张 `DAILY → 今日学习` 的表，与本版学习页的
/// 模式名（`每日综合`）并不一致——同一个模式在首页叫一个名字、在学习页叫另
/// 一个名字，用户会以为是两种东西。这里统一到学习页那一份。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/daos/study_dao.dart';
import 'package:lexiloop/features/dashboard/dashboard_navigation.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/section_card.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 整张卡片的 Key，供测试与无障碍定位。
const Key resumeSessionCardKey = Key('dashboard-resume-session');

/// 副标题（会话类型 · 剩余题数）的 Key，供测试断言文案。
const Key resumeSessionSubtitleKey = Key('dashboard-resume-subtitle');

/// 「继续」入口的 Key，供测试定位点击目标。
const Key resumeSessionContinueKey = Key('dashboard-resume-continue');

/// 「继续上次学习」卡片。
class ResumeSessionCard extends ConsumerWidget {
  /// 创建卡片。
  const new({this.embedded = false, super.key});

  /// 放在今日任务内时仅显示会话摘要，由任务主按钮负责继续。
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 加载中与失败都落到 `null`：两种情况下「有没有可恢复会话」都还未知，
    // 先渲染再撤掉比晚一拍出现更糟（见文件头注释）。
    final session = switch (ref.watch(resumableSessionProvider)) {
      AsyncData<ResumableSession?>(:final value) => value,
      _ => null,
    };
    if (session == null) return const SizedBox.shrink();
    if (embedded) {
      return Padding(
        key: resumeSessionCardKey,
        padding: const EdgeInsets.only(bottom: LexiSpace.s12),
        child: Text(
          '${studyModeLabel(session.mode)} · 还剩 ${session.remainingCount} 题',
          key: resumeSessionSubtitleKey,
          style: LexiType.body.copyWith(
            color: context.lexiColors.secondaryLabel,
          ),
        ),
      );
    }
    return SectionCard(
      tone: LexiTone.mint,
      key: resumeSessionCardKey,
      title: '继续上次学习',
      icon: LucideIcons.history,
      child: _ResumeSessionBody(session: session),
    );
  }
}

/// 卡片内容行：副标题 + 「继续 →」，整行可点。
class _ResumeSessionBody extends StatelessWidget {
  const new({required this.session});

  /// 要恢复的会话。
  final ResumableSession session;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    // 会话类型走学习页那一份中文名（见文件头注释），不另写一份映射。
    final subtitle =
        '${studyModeLabel(session.mode)} · 还剩 ${session.remainingCount} 题';
    return InkWell(
      key: resumeSessionContinueKey,
      onTap: () => goToStudyMode(context, session.mode),
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                subtitle,
                key: resumeSessionSubtitleKey,
                style: LexiType.body.copyWith(color: colors.secondaryLabel),
              ),
            ),
            Text(
              '继续',
              style: LexiType.body.copyWith(
                color: colors.accentText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: LexiSpace.s2),
            Icon(
              LucideIcons.arrowRight,
              size: resumeSessionArrowSize,
              color: colors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

/// 「继续 →」箭头字形尺寸。
///
/// 界面层的尺寸常量按本仓库惯例写在 feature 文件里（范例见
/// `lib/features/add/add_page.dart` 末尾），不往 `core/constants.dart` 塞。
const double resumeSessionArrowSize = 16;
