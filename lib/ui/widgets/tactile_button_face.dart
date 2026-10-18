/// 在标准按钮内绘制渐变、按压缩放与底部压暗，保留原生键盘、语义与涟漪。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';

/// 所有填充按钮共用的按压表面。
class TactileButtonFace extends StatelessWidget {
  /// 从标准按钮的状态构造。
  const new({required this.states, required this.child, super.key});

  /// 保留焦点、禁用、悬停与按下状态。
  final Set<WidgetState> states;

  /// 包含原按钮内边距的内容。
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final pressed = states.contains(WidgetState.pressed);
    final disabled = states.contains(WidgetState.disabled);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedScale(
      scale: pressed && !reduced ? LexiMotion.pressScale : 1,
      duration: reduced ? Duration.zero : LexiMotion.quick,
      curve: LexiMotion.spring,
      child: AnimatedContainer(
        duration: reduced ? Duration.zero : LexiMotion.quick,
        curve: LexiMotion.spring,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(LexiRadius.pill),
          gradient: disabled
              ? null
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[colors.accent, colors.accentDeep],
                ),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: pressed ? LexiTint.tint : LexiTint.subtle,
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}
