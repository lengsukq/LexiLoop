/// 学习会话的顶部进度与计数。
///
/// 学习页在沉浸模式下运行，外壳不提供导航，因此「跳过 / 结束」必须由这里
/// 自带；进度也在这里，让用户随时知道还剩多少。
///
/// **为什么是环而不是条**：进度条只能表达「比例」，剩下的题数还得另外写一行
/// 文字；而学习页最需要的恰好是那个数字。改成环之后，环内放已完成数、环的
/// 弧长表达比例、旁边一行说还剩多少——一个构件同时说清三件事，也成了学习页
/// 的识别符号。
///
/// 环的布局用 `Wrap`：360 宽下「环 + 文案」与「计数 + 动作」会自然折成两行，
/// 宽屏上则并成一行、左右分列。硬塞成一行会在窄屏溢出（实测）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 顶部进度与计数。
class StudyProgressHeader extends StatelessWidget {
  /// 以会话、跳过回调（为空表示禁用）与结束回调构造。
  const new({
    required this.session,
    required this.onSkip,
    required this.onExit,
    super.key,
  });

  /// 当前会话。
  final StudySessionView session;

  /// 跳过回调；提交后为 `null`，此时按钮禁用。
  final VoidCallback? onSkip;

  /// 结束回调。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LexiSpace.s20,
        LexiSpace.s12,
        LexiSpace.s20,
        LexiSpace.s8,
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: LexiSpace.s8,
        children: <Widget>[
          _SessionProgress(session: session),
          _CountsAndActions(session: session, onSkip: onSkip, onExit: onExit),
        ],
      ),
    );
  }
}

/// 进度环 + 「已完成 / 计划」+「还剩」。
class _SessionProgress extends StatelessWidget {
  const new({required this.session});

  final StudySessionView session;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final remaining = (session.plannedCount - session.completedCount).clamp(
      0,
      session.plannedCount,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _ProgressRing(
          completed: session.completedCount,
          planned: session.plannedCount,
        ),
        const SizedBox(width: LexiSpace.s12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              '${session.completedCount} / ${session.plannedCount}',
              style: LexiType.callout.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '还剩 $remaining 词',
              style: LexiType.caption.copyWith(color: colors.secondaryLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// 进度环。
class _ProgressRing extends StatelessWidget {
  const new({required this.completed, required this.planned});

  final int completed;
  final int planned;

  /// 直径——与可点区域下限同值，视觉重量与旁边的按钮一致。
  static const double diameter = studyMinTapTarget;

  /// 环的线宽。
  static const double strokeWidth = 4;

  /// 进度推进的时长。
  static const Duration transition = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final value = planned <= 0 ? 0.0 : (completed / planned).clamp(0.0, 1.0);

    return Semantics(
      label: '本轮进度',
      value: '$completed / $planned',
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value),
          duration: LexiMotion.of(context, transition),
          builder: (context, animated, child) => CustomPaint(
            painter: _ProgressRingPainter(
              value: animated,
              track: colors.fill,
              arc: colors.accent,
              strokeWidth: strokeWidth,
            ),
            child: child,
          ),
          // 环内的数字是**已完成数**：它是随作答增长的那个，也是用户扫一眼
          // 想确认的那个。比例由弧长表达，不再重复写成百分比。
          child: Center(
            child: Text(
              '$completed',
              style: LexiType.caption.copyWith(
                color: colors.label,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 画一个从 12 点开始、顺时针生长的环。
class _ProgressRingPainter extends CustomPainter {
  const new({
    required this.value,
    required this.track,
    required this.arc,
    required this.strokeWidth,
  });

  final double value;
  final Color track;
  final Color arc;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 线宽画在半径两侧，所以半径要减掉半个线宽，环才不会超出画布。
    final radius = (size.shortestSide - strokeWidth) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = track,
    );

    if (value <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = arc,
    );
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) =>
      old.value != value ||
      old.track != track ||
      old.arc != arc ||
      old.strokeWidth != strokeWidth;
}

/// 正确 / 错误计数与「跳过 / 结束」。
class _CountsAndActions extends StatelessWidget {
  const new({
    required this.session,
    required this.onSkip,
    required this.onExit,
  });

  final StudySessionView session;
  final VoidCallback? onSkip;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Wrap(
      spacing: LexiSpace.s6,
      runSpacing: LexiSpace.s8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _CountChip(
          label: '正确',
          value: session.correctCount,
          color: colors.success,
        ),
        _CountChip(
          label: '错误',
          value: session.wrongCount,
          color: colors.danger,
        ),
        const SizedBox(width: LexiSpace.s6),
        _HeaderAction(label: '跳过', enabled: onSkip != null, onTap: onSkip),
        _HeaderAction(label: '结束', enabled: true, onTap: onExit),
      ],
    );
  }
}

/// 单个计数胶囊。
///
/// **为什么不把状态色当文字**：饱和的系统色压在它自己 10% 的淡底上只有
/// 1.82–3.11:1（`success` 最差），而这里的文字是要读的。改成「中性底 +
/// 彩色圆点 + 常规文字色」——文字永远 ≥4.5:1，颜色仍然一眼可辨，而且不再
/// 只靠颜色传达信息（HIG `accessibility.md`）。
class _CountChip extends StatelessWidget {
  const new({required this.label, required this.value, required this.color});

  final String label;
  final int value;

  /// 圆点颜色（饱和色，用于区分，不承载文字）。
  final Color color;

  /// 圆点直径。
  static const double dotSize = 7;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Semantics(
      label: label,
      value: '$value',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s8,
          vertical: LexiSpace.s4,
        ),
        decoration: BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(LexiRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ExcludeSemantics(
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: LexiSpace.s6),
            ExcludeSemantics(
              child: Text(
                '$label $value',
                style: LexiType.caption.copyWith(
                  color: colors.secondaryLabel,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部的小动作按钮（跳过 / 结束）。
class _HeaderAction extends StatelessWidget {
  const new({required this.label, required this.enabled, required this.onTap});

  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: studyMinTapTarget,
        minWidth: 56,
      ),
      child: TextButton(
        onPressed: enabled ? onTap : null,
        child: Text(
          label,
          style: LexiType.body.copyWith(
            color: enabled ? colors.accentText : colors.quaternaryLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
