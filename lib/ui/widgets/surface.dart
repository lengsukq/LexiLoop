/// 按内容角色区分平整阅读面、重点词卡与内嵌块。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_depth.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';

/// 表面样式。
enum SurfaceVariant {
  /// 卡片：不透明底 + 发丝描边 + 静置影。用于承载内容的卡片与面板。
  card,

  /// 有柔和景深的重点词卡。
  raised,

  /// 今日任务等主焦点：主/次色低透明渐变 + 浮动影。
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
    final hero = variant == SurfaceVariant.hero;
    final radius =
        borderRadius ??
        BorderRadius.circular(
          hero
              ? LexiRadius.xl
              : inset
              ? LexiRadius.md
              : LexiRadius.lg,
        );
    if (variant == SurfaceVariant.plain) {
      return Padding(padding: padding ?? EdgeInsets.zero, child: child);
    }

    final toneStyle = tone == null ? null : context.lexiTones.styleOf(tone!);
    final base = inset
        ? colors.fill
        : lifted
        ? toneStyle?.background ?? colors.card
        : colors.card;
    final body = Padding(
      padding:
          padding ?? EdgeInsets.all(inset ? LexiSpace.s12 : surfaceCardPadding),
      child: child,
    );
    final content = Material(
      color: base,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: _borderSide(context, colors, inset: inset),
      ),
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: Colors.transparent,
      child: hero
          ? Stack(
              children: <Widget>[
                Positioned.fill(child: _heroWash(context)),
                body,
              ],
            )
          : body,
    );

    final shadows = switch (variant) {
      SurfaceVariant.hero => LexiDepth.of(
        LexiDepth.floating,
        LexiDepth.floatingDark,
        isDark: brightness == Brightness.dark,
      ),
      SurfaceVariant.raised => LexiDepth.of(
        LexiDepth.raised,
        LexiDepth.raisedDark,
        isDark: brightness == Brightness.dark,
      ),
      SurfaceVariant.card => LexiDepth.of(
        LexiDepth.resting,
        LexiDepth.restingDark,
        isDark: brightness == Brightness.dark,
      ),
      _ => const <BoxShadow>[],
    };
    if (shadows.isEmpty) return content;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadows),
      child: content,
    );
  }

  /// 描边：普通卡片一条发丝线，内嵌块不画；高对比度模式加重。
  BorderSide _borderSide(
    BuildContext context,
    LexiColors colors, {
    required bool inset,
  }) {
    if (inset) return BorderSide.none;
    if (MediaQuery.highContrastOf(context)) {
      return BorderSide(color: colors.borderStrong);
    }
    return BorderSide(color: colors.borderSubtle);
  }

  /// hero 卡的主/次色低透明渐变。
  Widget _heroWash(BuildContext context) {
    final colors = context.lexiColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colors.accent.withValues(alpha: dark ? 0.16 : 0.10),
            colors.secondary.withValues(alpha: dark ? 0.12 : 0.06),
          ],
        ),
      ),
    );
  }
}
