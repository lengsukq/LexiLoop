/// 通用可按压交互容器：自带微缩放（`0.98x`）、水波纹裁剪与触觉反馈。
///
/// 抽入 `lib/ui/widgets/` 的原因：
/// 词库卡片、练习入口卡片、选择题选项、底部抽屉条目都需要统一的移动端按压手感，
/// 业务层不应各自手写 `StatefulWidget` + `AnimatedScale` + `Material` + `InkWell`。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';

/// 移动端微缩放按压容器。
class LexiPressable extends StatefulWidget {
  /// 以子组件与点击回调构造。
  const new({
    required this.child,
    this.onTap,
    this.borderRadius,
    this.haptic = true,
    super.key,
  });

  /// 被包裹的内容。
  final Widget child;

  /// 点击回调；为 `null` 时禁用按压与缩放。
  final VoidCallback? onTap;

  /// 水波纹裁剪圆角；默认使用 `LexiRadius.lg`。
  final BorderRadius? borderRadius;

  /// 点击时是否触发轻触反馈。
  final bool haptic;

  @override
  State<LexiPressable> createState() => _LexiPressableState();
}

class _LexiPressableState extends State<LexiPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    final onTap = widget.onTap;
    if (onTap == null) return;
    if (widget.haptic) LexiHaptics.light();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final disableMotion = MediaQuery.disableAnimationsOf(context);
    final scale = (enabled && _pressed && !disableMotion)
        ? LexiMotion.pressScale
        : 1.0;
    final radius = widget.borderRadius ?? BorderRadius.circular(LexiRadius.lg);

    return AnimatedScale(
      scale: scale,
      duration: LexiMotion.of(context, LexiMotion.quick),
      curve: LexiMotion.spring,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? _handleTap : null,
          onHighlightChanged: enabled ? _setPressed : null,
          borderRadius: radius,
          child: widget.child,
        ),
      ),
    );
  }
}
