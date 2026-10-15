/// 对比度计算的共享实现（WCAG 2.x）。
///
/// 抽到 `test/support` 而不是各测试文件各写一份：设计守卫与组件测试必须
/// 用**同一套**公式，否则「守卫说 4.5、组件实际 4.1」这类漂移没人发现。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// [color] 的相对亮度。
double relativeLuminance(Color color) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 两个不透明颜色的对比度（1:1 ～ 21:1）。
double contrastRatio(Color foreground, Color background) {
  final a = relativeLuminance(foreground);
  final b = relativeLuminance(background);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}
