/// 内容分区的柔和彩色表面；与成功、错误等状态色分开。
///
/// **为什么从「固定色」改成「由主/次色微调」**：用户能换主色之后，四块
/// 固定薄荷/浅蓝/淡紫/杏色会成为页面上唯一不跟着主题走的颜色，主题就只
/// 换了按钮。这里保留各自的手调基色与明暗对比关系，只混入 12% 的主色或
/// 次色，让分区跟着主题轻微偏色，同时不破坏「分区 = 固定角色」的语义。
///
/// 前景色仍然逐对算过对比度：分区底色变了，文字色必须跟着重新收敛，
/// 否则「浅蓝底 + 深蓝字」在换了主色后会掉到 4.5:1 以下。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_color_math.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';

/// 固定角色的分区配色，明暗模式共用同一角色。
enum LexiTone {
  /// 主要学习内容与完成进度。
  mint,

  /// 资料、词典与统计。
  sky,

  /// 专项练习与配置。
  lavender,

  /// 学习建议与辅助提醒。
  peach,
}

/// 一个分区在**当前明暗模式**下解析完成的三支颜色。
@immutable
class LexiToneStyle {
  /// 以底色、前景色与描边构造。
  const new({
    required this.background,
    required this.foreground,
    required this.border,
  });

  /// 不透明分区底色。
  final Color background;

  /// 标题图标及强调文字。
  final Color foreground;

  /// 与底色同色系的细边框。
  final Color border;

  @override
  bool operator ==(Object other) =>
      other is LexiToneStyle &&
      other.background == background &&
      other.foreground == foreground &&
      other.border == border;

  @override
  int get hashCode => Object.hash(background, foreground, border);
}

/// 四个分区在当前主题下的解析结果。
@immutable
class LexiTones extends ThemeExtension<LexiTones> {
  /// 以四个分区样式构造。
  const new({
    required this.mint,
    required this.sky,
    required this.lavender,
    required this.peach,
  });

  /// 主要学习内容。
  final LexiToneStyle mint;

  /// 资料、词典与统计。
  final LexiToneStyle sky;

  /// 专项练习与配置。
  final LexiToneStyle lavender;

  /// 建议与提醒。
  final LexiToneStyle peach;

  /// 按角色取样式。
  LexiToneStyle styleOf(LexiTone tone) => switch (tone) {
    LexiTone.mint => mint,
    LexiTone.sky => sky,
    LexiTone.lavender => lavender,
    LexiTone.peach => peach,
  };

  /// 按当前色板与明暗模式推导四个分区。
  // ignore: prefer_constructors_over_static_methods
  static LexiTones resolve({
    required LexiColors colors,
    required Brightness brightness,
  }) {
    final dark = brightness == Brightness.dark;
    final primary = colors.accent;
    final secondary = colors.secondary;
    final mixed = Color.lerp(primary, secondary, 0.5)!;

    LexiToneStyle style({
      required Color background,
      required Color baseInk,
      required Color wash,
      double alpha = LexiTint.group,
    }) {
      final tinted = _keepReadable(
        Color.alphaBlend(wash.withValues(alpha: alpha), background),
        colors,
        dark: dark,
      );
      final ink = LexiColorMath.ensureReadable(baseInk, <Color>[
        tinted,
        colors.card,
      ]);
      return LexiToneStyle(
        background: tinted,
        foreground: ink,
        border: Color.alphaBlend(
          ink.withValues(alpha: LexiTint.border),
          tinted,
        ),
      );
    }

    return LexiTones(
      mint: style(
        background: dark ? _mintDark : _mintLight,
        baseInk: dark ? _mintInkDark : _mintInkLight,
        wash: primary,
        // 主分区承担「这一页的主色氛围」，比其他分区多混一点；
        // 底色本身已改成近中性，混 12% 不会把对比度吃光。
        alpha: LexiTint.tint,
      ),
      sky: style(
        background: dark ? _skyDark : _skyLight,
        baseInk: dark ? _skyInkDark : _skyInkLight,
        wash: secondary,
      ),
      lavender: style(
        background: dark ? _lavenderDark : _lavenderLight,
        baseInk: dark ? _lavenderInkDark : _lavenderInkLight,
        wash: mixed,
      ),
      peach: style(
        background: dark ? _peachDark : _peachLight,
        baseInk: dark ? _peachInkDark : _peachInkLight,
        wash: primary,
      ),
    );
  }

  /// 默认外观的浅色分区。
  static final LexiTones light = LexiTones.resolve(
    colors: LexiColors.light,
    brightness: Brightness.light,
  );

  /// 默认外观的深色分区。
  static final LexiTones dark = LexiTones.resolve(
    colors: LexiColors.dark,
    brightness: Brightness.dark,
  );

  @override
  LexiTones copyWith({
    LexiToneStyle? mint,
    LexiToneStyle? sky,
    LexiToneStyle? lavender,
    LexiToneStyle? peach,
  }) => LexiTones(
    mint: mint ?? this.mint,
    sky: sky ?? this.sky,
    lavender: lavender ?? this.lavender,
    peach: peach ?? this.peach,
  );

  @override
  LexiTones lerp(ThemeExtension<LexiTones>? other, double t) {
    if (other is! LexiTones) return this;
    LexiToneStyle blend(LexiToneStyle a, LexiToneStyle b) => LexiToneStyle(
      background: Color.lerp(a.background, b.background, t)!,
      foreground: Color.lerp(a.foreground, b.foreground, t)!,
      border: Color.lerp(a.border, b.border, t)!,
    );
    return LexiTones(
      mint: blend(mint, other.mint),
      sky: blend(sky, other.sky),
      lavender: blend(lavender, other.lavender),
      peach: blend(peach, other.peach),
    );
  }
}

/// 读取当前主题分区的便捷扩展。
extension LexiTonesContext on BuildContext {
  /// 当前主题下的分区色。
  LexiTones get lexiTones => Theme.of(this).extension<LexiTones>()!;
}

/// 染色之后再把底色往白/黑推一点，保证固定文字色仍然可读。
///
/// 分区的四个文字色是固定的语义色（含 `quaternaryLabel`），它们已经按
/// 页面底/卡片底验算过；染色只要让底变暗 1%，最弱的那一级就会掉到
/// 4.5:1 以下。这里以四级标签为最坏情况，按明暗方向小步修正。
Color _keepReadable(Color background, LexiColors colors, {required bool dark}) {
  var result = background;
  for (var i = 0; i < 12; i += 1) {
    if (LexiColorMath.contrast(colors.quaternaryLabel, result) >=
        LexiColorMath.minContrast) {
      break;
    }
    result = Color.lerp(result, dark ? Colors.black : Colors.white, 0.08)!;
  }
  return result;
}

// 手调基色。保留原先的色相与明暗关系，只作为「被主/次色微调」的底。
const Color _mintLight = Color(0xFFF1FAF6);
const Color _mintDark = Color(0xFF1B2B26);
const Color _mintInkLight = Color(0xFF146C4B);
const Color _mintInkDark = Color(0xFF86DAB5);

const Color _skyLight = Color(0xFFE5F1FF);
const Color _skyDark = Color(0xFF233446);
const Color _skyInkLight = Color(0xFF2B629C);
const Color _skyInkDark = Color(0xFF99C7FB);

const Color _lavenderLight = Color(0xFFF0EAFE);
const Color _lavenderDark = Color(0xFF342D46);
const Color _lavenderInkLight = Color(0xFF704DA3);
const Color _lavenderInkDark = Color(0xFFC8B0F1);

const Color _peachLight = Color(0xFFFFF0DF);
const Color _peachDark = Color(0xFF3B3027);
const Color _peachInkLight = Color(0xFF95531B);
const Color _peachInkDark = Color(0xFFEDC395);
