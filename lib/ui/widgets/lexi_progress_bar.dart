/// 带平滑动画过渡的通用圆角进度条。
///
/// 统一替换词库掌握概览、沉浸学习页顶栏、后台补全进度条中的手写
/// `ClipRRect + LinearProgressIndicator`。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_motion.dart';

/// 通用平滑动画进度条。
class LexiProgressBar extends StatelessWidget {
  /// 以 `0.0`–`1.0` 的进度值构造。
  const new({required this.value, this.color, this.height = 6, super.key});

  /// 当前进度（自动钳制在 `0.0`–`1.0` 之间）。
  final double value;

  /// 进度条主色；默认使用主题强调色。
  final Color? color;

  /// 轨道高度。
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final target = value.clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: target, end: target),
      duration: LexiMotion.of(context, LexiMotion.standard),
      curve: LexiMotion.spring,
      builder: (context, animatedValue, _) => ClipRRect(
        borderRadius: BorderRadius.circular(LexiRadius.pill),
        child: LinearProgressIndicator(
          value: animatedValue,
          minHeight: height,
          backgroundColor: colors.fill,
          color: color ?? colors.accent,
        ),
      ),
    );
  }
}
