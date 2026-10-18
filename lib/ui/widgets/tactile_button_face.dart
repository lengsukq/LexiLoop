/// 在标准按钮内绘制轻薄底沿，保留原生键盘、语义与涟漪。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_depth.dart';
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
    final pressed = states.contains(WidgetState.pressed);
    final disabled = states.contains(WidgetState.disabled);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedContainer(
      duration: reduced ? Duration.zero : LexiDepth.press,
      transform: Matrix4.translationValues(0, pressed && !reduced ? 2 : 0, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(LexiRadius.md),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.transparent,
            if (disabled)
              Colors.transparent
            else
              context.lexiColors.label.withValues(alpha: LexiTint.tint),
          ],
          stops: <double>[0, if (pressed) 0.98 else 0.94, 1],
        ),
      ),
      child: child,
    );
  }
}
