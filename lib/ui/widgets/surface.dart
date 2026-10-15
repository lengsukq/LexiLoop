/// 内容层的表面（standard material）。
///
/// **为什么内容层不能用液态玻璃**：Apple 的模型只有两层——内容层（文字、图片、
/// 列表、卡片）与功能层（侧边栏、工具栏、Tab Bar、弹窗）。Liquid Glass 属于
/// 功能层，`materials.md` 的原话是「**Don't use Liquid Glass in the content
/// layer.**… Instead, use standard materials for elements in the content layer,
/// such as app backgrounds」。玻璃压在玻璃上会让所有卡片落在同一层材质上，
/// 层级只能靠间距硬撑——这正是界面「看起来不统一」的根源。
///
/// 所以：卡片、列表容器、表单用 [Surface]（不透明 + 发丝描边），
/// 只有侧边栏 / 底部栏 / 沉浸式 HUD / 弹窗才用 `LiquidGlass`。
///
/// 顺带的收益：少掉几十个全屏 `BackdropFilter`，低端设备不必再走模糊降级。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';

/// 表面样式。
enum SurfaceVariant {
  /// 卡片：不透明底 + 发丝描边 + 极轻投影。用于承载内容的卡片与面板。
  card,

  /// 内嵌块：`fill` 淡底、无描边。用于卡片内部再分组的元素
  /// （选项行、输入容器、统计格）。
  inset,

  /// 纯分组：不画任何底与描边，只提供统一的圆角与内边距语义。
  plain,
}

/// 卡片内的默认内边距。
const double surfaceCardPadding = LexiSpace.s20;

/// 卡片投影的模糊半径。
const double _cardShadowBlur = 2;

/// 卡片投影的垂直偏移。
const double _cardShadowOffsetY = 1;

/// 内容层的一张表面。
class Surface extends StatelessWidget {
  /// 以内容构造。
  const new({
    required this.child,
    this.variant = SurfaceVariant.card,
    this.padding,
    this.borderRadius,
    super.key,
  });

  /// 表面上的内容。
  final Widget child;

  /// 表面样式。
  final SurfaceVariant variant;

  /// 内边距；为空时卡片用 [surfaceCardPadding]，内嵌块用 `LexiSpace.s12`。
  final EdgeInsetsGeometry? padding;

  /// 圆角；为空时卡片用 `LexiRadius.lg`，内嵌块用 `LexiRadius.md`。
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 打开「增强对比度」时把描边加重：这是系统给我们的唯一信号
    // （Flutter 没有暴露「减弱透明度」）。
    final highContrast = MediaQuery.highContrastOf(context);

    final resolvedRadius =
        borderRadius ??
        BorderRadius.circular(
          variant == SurfaceVariant.inset ? LexiRadius.md : LexiRadius.lg,
        );

    if (variant == SurfaceVariant.plain) {
      return Padding(padding: padding ?? EdgeInsets.zero, child: child);
    }

    final isInset = variant == SurfaceVariant.inset;
    final decoration = BoxDecoration(
      color: isInset
          ? colors.fill
          : (isDark ? const Color(0xFF1C1C1E) : Colors.white),
      borderRadius: resolvedRadius,
      border: isInset
          ? null
          : Border.all(
              color: highContrast ? colors.borderStrong : colors.borderSubtle,
            ),
      boxShadow: isInset
          ? null
          : <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
                blurRadius: _cardShadowBlur,
                offset: const Offset(0, _cardShadowOffsetY),
              ),
            ],
    );

    final resolvedPadding =
        padding ?? EdgeInsets.all(isInset ? LexiSpace.s12 : surfaceCardPadding);

    return DecoratedBox(
      decoration: decoration,
      child: Padding(padding: resolvedPadding, child: child),
    );
  }
}
