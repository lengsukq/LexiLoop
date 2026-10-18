/// 按内容角色区分平整阅读面与重点词卡。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_depth.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';

/// 表面样式。
enum SurfaceVariant {
  /// 卡片：不透明底 + 发丝描边 + 极轻投影。用于承载内容的卡片与面板。
  card,

  /// 有柔和景深的重点词卡。
  raised,

  /// 今日任务等主焦点。
  hero,

  /// 内嵌块：`fill` 淡底、无描边。用于卡片内部再分组的元素
  /// （选项行、输入容器、统计格）。
  inset,

  /// 纯分组：不画任何底与描边，只提供统一的圆角与内边距语义。
  plain,
}

/// 卡片内的默认内边距。
const double surfaceCardPadding = LexiSpace.s20;

/// 内容层的一张表面。
class Surface extends StatelessWidget {
  /// 以内容构造。
  const new({
    required this.child,
    this.variant = SurfaceVariant.card,
    this.padding,
    this.borderRadius,
    this.tone,
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

  /// 可选的分区色；不指定时保留阅读用的中性表面。
  final LexiTone? tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final brightness = Theme.of(context).brightness;
    final lifted =
        variant == SurfaceVariant.raised || variant == SurfaceVariant.hero;
    final inset = variant == SurfaceVariant.inset;
    final radius =
        borderRadius ??
        BorderRadius.circular(
          variant == SurfaceVariant.hero
              ? LexiRadius.xl
              : inset
              ? LexiRadius.md
              : LexiRadius.lg,
        );
    if (variant == SurfaceVariant.plain) {
      return Padding(padding: padding ?? EdgeInsets.zero, child: child);
    }
    final content = Material(
      color: inset
          ? colors.fill
          : lifted
          ? tone?.background(brightness) ?? colors.card
          : colors.card,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: MediaQuery.highContrastOf(context)
            ? BorderSide(color: colors.borderStrong)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding:
            padding ??
            EdgeInsets.all(inset ? LexiSpace.s12 : surfaceCardPadding),
        child: child,
      ),
    );
    if (!lifted) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: brightness == Brightness.dark
            ? LexiDepth.raisedDark
            : LexiDepth.raised,
      ),
      child: content,
    );
  }
}
