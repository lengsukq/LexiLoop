/// 液态玻璃（Liquid Glass）视觉系统。
///
/// 复刻旧版 `src/app/styles/glass.css` 的 4 个层级。旧版靠 CSS
/// `backdrop-filter: blur(N) saturate(M)`，Flutter 侧用 `BackdropFilter` +
/// `ImageFilter.compose` 实现。
///
/// **三个已知的还原难点**（旧版 CSS 与 Flutter 不完全一一对应）：
/// 1. `saturate()` 在 Flutter 没有一行 API，必须自己构造 4x5 颜色矩阵；
/// 2. 旧版 `.liquid-glass` 的 `border-color` 与 `border-bottom-color` 不等
///    （.55 与 .25），需要用逐边 `Border` 而非统一 `Border.all`；
/// 3. 全屏多层大半径模糊在低端 Android 会掉帧，由 `PlatformCaps` 决定是否降级。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/platform.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';

/// 玻璃层级的强度档位，对应旧版 CSS 的 4 个类。
enum GlassLevel {
  /// 导航栏、Tab Bar、浮动胶囊（旧版 `.liquid-glass`，blur 24 / saturate 175%）。
  base(blurSigma: 24, saturation: 1.75),

  /// 主卡片、对话框、浮动面板（旧版 `.liquid-glass-elevated`，blur 30 / saturate 180%）。
  elevated(blurSigma: 30, saturation: 1.8),

  /// 卡片内部子元素（旧版 `.glass-inner`，blur 18 / saturate 160%）。
  inner(blurSigma: 18, saturation: 1.6),

  /// 芯片、次级面板、输入容器（旧版 `.liquid-glass-subtle`，blur 14 / saturate 150%）。
  subtle(blurSigma: 14, saturation: 1.5);

  new({required this.blurSigma, required this.saturation});

  /// 高斯模糊的标准差。
  ///
  /// CSS `blur(N)` 的参数就是高斯标准差，故与 Flutter 的 `sigmaX/Y` 直接对应，
  /// 不需要按「半径 vs 标准差」换算。
  final double blurSigma;

  /// 饱和度倍率。
  final double saturation;
}

/// 构造饱和度调整的颜色矩阵。
///
/// 使用 Rec. 709 亮度权重（0.213 / 0.715 / 0.072），与浏览器
/// `filter: saturate()` 的实现一致。
List<double> _saturationMatrix(double s) {
  const lr = 0.213;
  const lg = 0.715;
  const lb = 0.072;
  return <double>[
    lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0, //
    lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0, //
  ];
}

/// 一块液态玻璃面板。
///
/// 典型用法是作为侧边栏、Tab Bar、卡片或对话框的容器。
class LiquidGlass extends StatelessWidget {
  /// 创建液态玻璃面板。
  const new({
    required this.child,
    this.level = GlassLevel.base,
    this.borderRadius,
    this.padding,
    this.showSpecular = false,
    this.showEdge = false,
    this.clipBehavior = Clip.antiAlias,
    super.key,
  });

  /// 面板内容。
  final Widget child;

  /// 强度档位。
  final GlassLevel level;

  /// 圆角；为空时不做圆角裁切。
  final BorderRadius? borderRadius;

  /// 内边距。
  final EdgeInsetsGeometry? padding;

  /// 是否叠加顶部高光（旧版 `.liquid-glass-specular`）。
  final bool showSpecular;

  /// 是否叠加底部边缘光（旧版 `.liquid-glass-edge`）。
  final bool showEdge;

  /// 裁切行为。
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.zero;

    // 低端 Android 上把模糊半径减半，避免全屏多层模糊掉到 40fps 以下。
    final sigma = PlatformCaps.needsBlurDowngrade
        ? level.blurSigma * 0.5
        : level.blurSigma;

    return ClipRRect(
      borderRadius: radius,
      clipBehavior: clipBehavior,
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(_saturationMatrix(level.saturation)),
          inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        ),
        child: DecoratedBox(
          decoration: _decoration(isDark, radius),
          child: Stack(
            children: <Widget>[
              if (showSpecular) _specular(isDark, radius),
              if (showEdge) _edge(isDark),
              // 边框必须用 CustomPainter 画：Flutter 的 BoxDecoration.border
              // 在带圆角时要求四边同色，无法还原旧版「上亮下暗」的描边。
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GlassBorderPainter(
                      radius: radius,
                      topColor: isDark
                          ? LexiGlassPalette.borderTopDark
                          : LexiGlassPalette.borderTopLight,
                      bottomColor: isDark
                          ? LexiGlassPalette.borderBottomDark
                          : LexiGlassPalette.borderBottomLight,
                    ),
                  ),
                ),
              ),
              Padding(padding: padding ?? EdgeInsets.zero, child: child),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _decoration(bool isDark, BorderRadius radius) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: level == GlassLevel.elevated
            ? const Alignment(-0.45, -1)
            : Alignment.topLeft,
        end: level == GlassLevel.elevated
            ? const Alignment(0.45, 1)
            : Alignment.bottomRight,
        colors: <Color>[
          if (isDark)
            LexiGlassPalette.gradientTopDark
          else
            LexiGlassPalette.gradientTopLight,
          if (isDark)
            LexiGlassPalette.gradientBottomDark
          else
            LexiGlassPalette.gradientBottomLight,
        ],
      ),
      borderRadius: radius,
      boxShadow: <BoxShadow>[
        BoxShadow(
          color: isDark
              ? LexiGlassPalette.shadowDark
              : LexiGlassPalette.shadowLight,
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// 顶部折射高光，对应旧版 `.liquid-glass-specular::before`。
  Widget _specular(bool isDark, BorderRadius radius) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: const Alignment(0, -0.1),
              colors: <Color>[
                Colors.white.withValues(alpha: isDark ? 0.06 : 0.45),
                Colors.white.withValues(alpha: LexiTint.none),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 底部 1px 边缘光，对应旧版 `.liquid-glass-edge::after`。
  Widget _edge(bool isDark) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Colors.white.withValues(alpha: LexiTint.none),
                Colors.white.withValues(alpha: isDark ? 0.25 : 0.65),
                Colors.white.withValues(alpha: LexiTint.none),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 全局中性页面底色。沿用入口名称以兼容外壳与顶层路由，
/// 不再绘制装饰光斑，内容层的层级由表面与留白表达。
class AmbientBackground extends StatelessWidget {
  /// 创建环境光背景。
  const new({required this.child, super.key});

  /// 背景之上的内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: context.lexiColors.surface, child: child);
  }
}

/// 用垂直渐变绘制圆角描边。
///
/// **为什么不用 `BoxDecoration.border`**：Flutter 在设置了 `borderRadius`
/// 时要求边框四边颜色一致，否则绘制阶段抛
/// `A borderRadius can only be given on borders with uniform colors`。
/// 而旧版 `glass.css` 的描边正是「上亮下暗」（.55 → .25），
/// 用渐变描边既绕开该限制，又比逐边硬切更接近原设计。
class _GlassBorderPainter extends CustomPainter {
  const new({
    required this.radius,
    required this.topColor,
    required this.bottomColor,
  });

  final BorderRadius radius;
  final Color topColor;
  final Color bottomColor;

  /// 描边宽度。
  static const double strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[topColor, bottomColor],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    // 内缩半个描边宽度，避免描边被圆角裁掉一半。
    canvas.drawRRect(radius.toRRect(rect).deflate(strokeWidth / 2), paint);
  }

  @override
  bool shouldRepaint(_GlassBorderPainter oldDelegate) {
    return oldDelegate.radius != radius ||
        oldDelegate.topColor != topColor ||
        oldDelegate.bottomColor != bottomColor;
  }
}
