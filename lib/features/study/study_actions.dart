/// 学习页吸底动作条：作答阶段与选择题倒计时。
///
/// 动作条由 `PageShell` 固定在底部（见 `ui/widgets/page_shell.dart`），
/// 因此判定与「下一题」不会因为题目变长而被推到折叠线以外——旧版把反馈卡
/// 和「下一题」放在滚动内容末尾，用户提交后必须先滚动才能继续。
///
/// 揭示后这里换成自评条（`study_rating.dart`），自评即提交并自动前进，
/// 不再有第二个「下一题」动作。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/surface.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 宽屏主按钮的宽度上限。
///
/// 学习页是沉浸页，主按钮铺满 840 会变成一条横幅；按内容取宽、靠右对齐。
const double studyPrimaryActionWidth = 220;

/// 文本类题目的动作条：稍后再学 / 忘记 / 检查答案。
class StudyCheckActions extends StatelessWidget {
  /// 以可用性、主按钮文案与三个回调构造。
  const new({
    required this.canCheck,
    required this.primaryLabel,
    required this.onSkip,
    required this.onCheck,
    this.onForget,
    super.key,
  });

  /// 主按钮是否可点（文本题要已有输入）。
  final bool canCheck;

  /// 主按钮文案：检查答案 / 显示答案。
  final String primaryLabel;

  /// 稍后再学回调。
  final VoidCallback onSkip;

  /// 检查答案 / 显示答案回调。
  final VoidCallback onCheck;

  /// 忘记回调；为 `null` 时不显示该按钮。
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    final primary = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: studyButtonHeight),
      child: FilledButton(
        onPressed: canCheck ? onCheck : null,
        child: Text(primaryLabel),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= studyWideMinWidth;
        final secondary = _secondaryRow(context);
        if (wide) {
          return Row(
            children: <Widget>[
              ...secondary,
              const Spacer(),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: studyPrimaryActionWidth,
                ),
                child: primary,
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(children: secondary),
            const SizedBox(height: LexiSpace.s8),
            primary,
          ],
        );
      },
    );
  }

  /// 次要动作：稍后再学与（可选的）忘记。
  List<Widget> _secondaryRow(BuildContext context) {
    final colors = context.lexiColors;
    return <Widget>[
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: studyMinTapTarget),
        child: OutlinedButton.icon(
          onPressed: onSkip,
          icon: const Icon(LucideIcons.clock, size: 16),
          label: const Text('稍后再学'),
        ),
      ),
      if (onForget != null) ...<Widget>[
        const SizedBox(width: LexiSpace.s8),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: studyMinTapTarget),
          child: OutlinedButton.icon(
            onPressed: onForget,
            style: OutlinedButton.styleFrom(
              foregroundColor: colors.dangerText,
              side: BorderSide(
                color: colors.danger.withValues(alpha: LexiTint.tint),
              ),
            ),
            icon: const Icon(LucideIcons.circleX, size: 16),
            label: const Text('忘记'),
          ),
        ),
      ],
    ];
  }
}

/// 选择题的动作条：稍后再学 + 当前阶段的提示。
///
/// 选择题没有「检查答案」主按钮：点选项本身就是揭示动作，选项还没出现时
/// 由 [StudyChoiceGate] 提供「立即显示选项」。
class StudyChoiceActions extends StatelessWidget {
  /// 以提示语与稍后再学回调构造。
  const new({required this.hint, required this.onSkip, super.key});

  /// 当前阶段的操作提示。
  final String hint;

  /// 稍后再学回调。
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Row(
      children: <Widget>[
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: studyMinTapTarget),
          child: OutlinedButton.icon(
            onPressed: onSkip,
            icon: const Icon(LucideIcons.clock, size: 16),
            label: const Text('稍后再学'),
          ),
        ),
        const SizedBox(width: LexiSpace.s12),
        Expanded(
          child: Text(
            hint,
            textAlign: TextAlign.end,
            style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
          ),
        ),
      ],
    );
  }
}

/// 选择题的选项倒计时。
///
/// 设置里的「揭示延迟」原先是一个死开关：设置页能调，学习页却从不读取。
/// 这里按 Next 版的做法，在选项出现前留出回忆时间，并允许立即跳过等待。
class StudyChoiceGate extends StatelessWidget {
  /// 以进度、剩余秒数与立即显示回调构造。
  const new({
    required this.progress,
    required this.remainingSeconds,
    required this.onRevealNow,
    super.key,
  });

  /// 已等待比例，0–1。
  final double progress;

  /// 剩余秒数（向上取整，至少 1）。
  final int remainingSeconds;

  /// 立即显示选项回调。
  final VoidCallback onRevealNow;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Surface(
      variant: SurfaceVariant.inset,
      padding: const EdgeInsets.all(LexiSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(LucideIcons.eye, size: 16, color: colors.accentText),
              const SizedBox(width: LexiSpace.s8),
              Expanded(
                child: Text(
                  '$remainingSeconds 秒后显示选项',
                  style: LexiType.body.copyWith(color: colors.secondaryLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: LexiSpace.s10),
          ClipRRect(
            borderRadius: BorderRadius.circular(LexiRadius.xs),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: LexiSpace.s4,
            ),
          ),
          const SizedBox(height: LexiSpace.s10),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: studyMinTapTarget),
              child: TextButton.icon(
                onPressed: onRevealNow,
                icon: const Icon(LucideIcons.eye, size: 16),
                label: const Text('立即显示选项'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
