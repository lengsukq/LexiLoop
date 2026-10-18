/// LexiLoop 的语义色与圆角：清透蓝底、可换主色与柔和彩色分区。
///
/// 用 `ThemeExtension` 而非散落的常量，好处是随 `Theme.of(context)` 自动
/// 切换明暗，组件不需要判断当前模式。旧版靠 CSS 变量 + 媒体查询达到同样效果。
///
/// **主色/次色可换之后，色板不再是一份写死的常量**：中性色（页面底、卡片、
/// 四级文字、分隔线、边框）仍然固定，强调色与次色由用户选的色种推导；
/// 推导保证「文字压在任何自有背景上 ≥4.5:1」，见 [LexiColorMath]。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/ui/theme/lexi_color_math.dart';

/// LexiLoop 的语义色板。
///
/// 明暗两套语义角色由主题统一注入，组件不自行拼装色板。
@immutable
class LexiColors extends ThemeExtension<LexiColors> {
  /// 创建一份色板。
  const new({
    required this.surface,
    required this.card,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.quaternaryLabel,
    required this.accent,
    required this.accentDeep,
    required this.secondary,
    required this.secondaryDeep,
    required this.danger,
    required this.dangerDeep,
    required this.success,
    required this.successDeep,
    required this.warning,
    required this.warningDeep,
    required this.purple,
    required this.purpleDeep,
    required this.accentText,
    required this.secondaryText,
    required this.dangerText,
    required this.successText,
    required this.warningText,
    required this.purpleText,
    required this.separator,
    required this.fill,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
  });

  /// 页面底色（`--ll-surface`）。
  final Color surface;

  /// 卡片底色——内容层表面（`Surface`）的不透明底。
  ///
  /// 浅色用纯白、深色用 `#232D3F`：卡片必须与页面底拉开一档，否则发丝
  /// 描边就成了唯一的层级线索。
  final Color card;

  /// 主文本色（`--ll-label`）。
  final Color label;

  /// 次级文本色（`--ll-secondary-label`）。
  final Color secondaryLabel;

  /// 三级文本色（`--ll-tertiary-label`）。
  final Color tertiaryLabel;

  /// 四级文本色（`--ll-quaternary-label`）。
  final Color quaternaryLabel;

  /// 主强调色：用户选择的主色，用于主动作、选中和进度。
  final Color accent;

  /// 强调色的深色变体（渐变终点、按压态）。
  final Color accentDeep;

  /// 次强调色：用户选择的次色，用于次级动作、双色渐变与图表第二序列。
  final Color secondary;

  /// 次色的深色变体。
  final Color secondaryDeep;

  /// 危险色（`--ll-danger`）。
  final Color danger;

  /// 危险色深色变体（`--ll-danger-deep`）。
  final Color dangerDeep;

  /// 成功色（`--ll-success`）。
  final Color success;

  /// 成功色深色变体（`--ll-success-deep`）。
  final Color successDeep;

  /// 警告色（`--ll-warning`）。
  final Color warning;

  /// 警告色深色变体（`--ll-warning-deep`）。
  final Color warningDeep;

  /// 紫色强调（`--ll-purple`）；语义固定，表示关联词等辅助分类。
  final Color purple;

  /// 紫色深色变体（`--ll-purple-deep`）。
  final Color purpleDeep;

  /// 强调色作为**文字**时的取值。
  ///
  /// 饱和的 [accent] 只适合做填充、圆点与进度条：它当文字压在浅色底上
  /// 往往不足 4.5:1。这一组是按当前主色算出来的、在页面底/卡片底/淡底上
  /// 都 ≥4.5:1 的文字色。
  final Color accentText;

  /// 次色作为文字时的取值。
  final Color secondaryText;

  /// 危险色作为文字时的取值。
  final Color dangerText;

  /// 成功色作为文字时的取值。
  final Color successText;

  /// 警告色作为文字时的取值。
  final Color warningText;

  /// 紫色作为文字时的取值。
  final Color purpleText;

  /// 分隔线（`--ll-separator`）。
  final Color separator;

  /// 填充底色（`--ll-fill`）。
  final Color fill;

  /// 最弱的边框（`--ll-border-subtle`）。
  final Color borderSubtle;

  /// 默认边框（`--ll-border-default`）。
  final Color borderDefault;

  /// 最强的边框（`--ll-border-strong`）。
  final Color borderStrong;

  /// 按色种与明暗模式推导整套色板。
  ///
  /// 中性色固定；强调色、次色及其文字色由 [LexiColorMath] 校准。
  // ignore: prefer_constructors_over_static_methods
  static LexiColors resolve({
    required Color primarySeed,
    required Color secondarySeed,
    required Brightness brightness,
  }) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF171D2B) : const Color(0xFFF3F6FC);
    final card = dark ? const Color(0xFF232D3F) : const Color(0xFFFFFFFF);
    final fill = dark
        ? const Color.fromRGBO(120, 120, 128, 0.18)
        : const Color.fromRGBO(78, 116, 173, 0.08);

    final accent = LexiColorMath.accent(primarySeed, dark: dark);
    final secondary = LexiColorMath.accent(secondarySeed, dark: dark);
    // 文字色要在页面底、卡片底与「淡底压卡片」三种背景上都站得住。
    // 少算最后一种，徽章/内嵌块里的彩色文字就会掉到 4:1 以下。
    final backgrounds = <Color>[
      surface,
      card,
      Color.alphaBlend(fill, card),
      Color.alphaBlend(fill, surface),
    ];
    final accentText = LexiColorMath.ensureReadable(
      LexiColorMath.deepen(accent, dark: dark),
      backgrounds,
      // 比 4.5 多留一点余量：同样的文字还会压在四种分区底色上，
      // 只按页面底/卡片底卡到 4.5 会让「淡蓝分区 + 主色文字」掉到 4.44。
      min: 4.8,
    );
    final secondaryText = LexiColorMath.ensureReadable(
      LexiColorMath.deepen(secondary, dark: dark),
      backgrounds,
      min: 4.8,
    );

    return LexiColors(
      surface: surface,
      card: card,
      label: dark ? const Color(0xFFE8EDF7) : const Color(0xFF252B3B),
      // 四级标签按「对比度单调递减」取值，且**每一级都 ≥4.5:1**。
      secondaryLabel: dark ? const Color(0xFFAFBACC) : const Color(0xFF586275),
      tertiaryLabel: dark ? const Color(0xFFA3AFC2) : const Color(0xFF60697A),
      quaternaryLabel: dark ? const Color(0xFF9AA6BA) : const Color(0xFF626A7A),
      accent: accent,
      accentDeep: LexiColorMath.deepen(accent, dark: dark),
      secondary: secondary,
      secondaryDeep: LexiColorMath.deepen(secondary, dark: dark),
      danger: dark ? const Color(0xFFFF453A) : const Color(0xFFFF3B30),
      dangerDeep: dark ? const Color(0xFFFF453A) : const Color(0xFFD70015),
      success: dark ? const Color(0xFF91C9AE) : const Color(0xFF49816A),
      successDeep: dark ? const Color(0xFF91C9AE) : const Color(0xFF248A3D),
      warning: dark ? const Color(0xFFFF9F0A) : const Color(0xFFFF9500),
      warningDeep: dark ? const Color(0xFFFF9F0A) : const Color(0xFFC93400),
      purple: dark ? const Color(0xFFBF5AF2) : const Color(0xFFAF52DE),
      purpleDeep: dark ? const Color(0xFFBF5AF2) : const Color(0xFF8944AB),
      accentText: accentText,
      secondaryText: secondaryText,
      dangerText: dark ? const Color(0xFFFFA198) : const Color(0xFFC2140F),
      successText: dark ? const Color(0xFF91C9AE) : const Color(0xFF146B31),
      warningText: dark ? const Color(0xFFFF9F0A) : const Color(0xFF8A5200),
      purpleText: dark ? const Color(0xFFD6ADE8) : const Color(0xFF7A3B99),
      separator: dark
          ? const Color.fromRGBO(84, 84, 88, 0.34)
          : const Color.fromRGBO(60, 60, 67, 0.12),
      fill: fill,
      borderSubtle: dark
          ? const Color.fromRGBO(255, 255, 255, 0.08)
          : const Color.fromRGBO(60, 60, 67, 0.08),
      borderDefault: dark
          ? const Color.fromRGBO(255, 255, 255, 0.14)
          : const Color.fromRGBO(60, 60, 67, 0.14),
      borderStrong: dark
          ? const Color.fromRGBO(255, 255, 255, 0.24)
          : const Color.fromRGBO(60, 60, 67, 0.24),
    );
  }

  /// 默认主色/次色的浅色色板。
  static final LexiColors light = LexiColors.resolve(
    primarySeed: const Color(defaultThemePrimaryColor),
    secondarySeed: const Color(defaultThemeSecondaryColor),
    brightness: Brightness.light,
  );

  /// 默认主色/次色的深色色板。
  static final LexiColors dark = LexiColors.resolve(
    primarySeed: const Color(defaultThemePrimaryColor),
    secondarySeed: const Color(defaultThemeSecondaryColor),
    brightness: Brightness.dark,
  );

  /// 强调色上的文字。
  Color get onAccent => LexiColorMath.bestOn(accent);

  /// 次色上的文字。
  Color get onSecondary => LexiColorMath.bestOn(secondary);

  /// 危险色上的文字。
  Color get onDanger => LexiColorMath.bestOn(danger);

  @override
  LexiColors copyWith({
    Color? surface,
    Color? label,
    Color? secondaryLabel,
    Color? tertiaryLabel,
    Color? quaternaryLabel,
    Color? accent,
    Color? accentDeep,
    Color? secondary,
    Color? secondaryDeep,
    Color? danger,
    Color? dangerDeep,
    Color? success,
    Color? successDeep,
    Color? warning,
    Color? warningDeep,
    Color? purple,
    Color? purpleDeep,
    Color? accentText,
    Color? secondaryText,
    Color? dangerText,
    Color? successText,
    Color? warningText,
    Color? purpleText,
    Color? card,
    Color? separator,
    Color? fill,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
  }) {
    return LexiColors(
      surface: surface ?? this.surface,
      card: card ?? this.card,
      label: label ?? this.label,
      secondaryLabel: secondaryLabel ?? this.secondaryLabel,
      tertiaryLabel: tertiaryLabel ?? this.tertiaryLabel,
      quaternaryLabel: quaternaryLabel ?? this.quaternaryLabel,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      secondary: secondary ?? this.secondary,
      secondaryDeep: secondaryDeep ?? this.secondaryDeep,
      danger: danger ?? this.danger,
      dangerDeep: dangerDeep ?? this.dangerDeep,
      success: success ?? this.success,
      successDeep: successDeep ?? this.successDeep,
      warning: warning ?? this.warning,
      warningDeep: warningDeep ?? this.warningDeep,
      purple: purple ?? this.purple,
      purpleDeep: purpleDeep ?? this.purpleDeep,
      accentText: accentText ?? this.accentText,
      secondaryText: secondaryText ?? this.secondaryText,
      dangerText: dangerText ?? this.dangerText,
      successText: successText ?? this.successText,
      warningText: warningText ?? this.warningText,
      purpleText: purpleText ?? this.purpleText,
      separator: separator ?? this.separator,
      fill: fill ?? this.fill,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderDefault: borderDefault ?? this.borderDefault,
      borderStrong: borderStrong ?? this.borderStrong,
    );
  }

  @override
  LexiColors lerp(ThemeExtension<LexiColors>? other, double t) {
    if (other is! LexiColors) return this;
    return LexiColors(
      surface: Color.lerp(surface, other.surface, t)!,
      card: Color.lerp(card, other.card, t)!,
      label: Color.lerp(label, other.label, t)!,
      secondaryLabel: Color.lerp(secondaryLabel, other.secondaryLabel, t)!,
      tertiaryLabel: Color.lerp(tertiaryLabel, other.tertiaryLabel, t)!,
      quaternaryLabel: Color.lerp(quaternaryLabel, other.quaternaryLabel, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      secondaryDeep: Color.lerp(secondaryDeep, other.secondaryDeep, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerDeep: Color.lerp(dangerDeep, other.dangerDeep, t)!,
      success: Color.lerp(success, other.success, t)!,
      successDeep: Color.lerp(successDeep, other.successDeep, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningDeep: Color.lerp(warningDeep, other.warningDeep, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      purpleDeep: Color.lerp(purpleDeep, other.purpleDeep, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      dangerText: Color.lerp(dangerText, other.dangerText, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      purpleText: Color.lerp(purpleText, other.purpleText, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
      fill: Color.lerp(fill, other.fill, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderDefault: Color.lerp(borderDefault, other.borderDefault, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
    );
  }
}

/// LexiLoop 的圆角档位。
///
/// 2026-10-18 起整体上调一档：iOS 26 的卡片与浮层比旧版更圆，小圆角
/// 会被读成「网页表格」。`xxs` 保持 4，只给边长 12–16 的微型元素。
abstract final class LexiRadius {
  /// 微型圆角（4px）——热力图小方块、行内 diff 标签。
  static const double xxs = 4;

  /// 极小圆角（8px）——内嵌的小标签、输入框内的色块。
  static const double xs = 8;

  /// 小圆角（12px）——标签、徽章、图标底盘。
  static const double sm = 12;

  /// 中圆角（16px）——输入框、内嵌块。
  static const double md = 16;

  /// 大圆角（22px）——卡片。
  static const double lg = 22;

  /// 特大圆角（28px）——hero 卡、浮层、对话框。
  static const double xl = 28;

  /// 最大圆角（34px）——底部 Sheet、导航胶囊。
  static const double xxl = 34;

  /// 胶囊圆角——计数胶囊、筛选 chip、按钮。
  ///
  /// 用一个大到「一定超过元素半高」的值表达胶囊形状；Flutter 会把圆角
  /// 夹到半高，因此不需要按元素尺寸计算。
  static const double pill = 999;

  /// 全部档位（不含 [pill]——那是形状哨兵，不是可插值的档位）。
  static const List<double> steps = <double>[xxs, xs, sm, md, lg, xl, xxl];
}

/// 读取当前主题色板的便捷扩展。
extension LexiColorsContext on BuildContext {
  /// 当前主题下的 LexiLoop 色板。
  LexiColors get lexiColors => Theme.of(this).extension<LexiColors>()!;
}

/// 玻璃配色。
///
/// 功能层采用中性高光与深底，集中定义避免散落在构建逻辑里，
/// 也便于后续按视觉稿微调时只改一处。
abstract final class LexiGlassPalette {
  /// 渐变起始色（顶部高光）。
  static const Color gradientTopLight = Color.fromRGBO(255, 255, 255, 0.68);

  /// 深色顶部高光。
  static const Color gradientTopDark = Color.fromRGBO(255, 255, 255, 0.09);

  /// 渐变结束色（主体底色）。
  static const Color gradientBottomLight = Color.fromRGBO(255, 255, 255, 0.62);

  /// 深色主体底。
  static const Color gradientBottomDark = Color.fromRGBO(34, 42, 37, 0.86);

  /// 上边框——旧版此边显著亮于下边框（.55 vs .25）。
  static const Color borderTopLight = Color.fromRGBO(255, 255, 255, 0.55);

  /// 深色上边框。
  static const Color borderTopDark = Color.fromRGBO(255, 255, 255, 0.14);

  /// 下边框。
  static const Color borderBottomLight = Color.fromRGBO(255, 255, 255, 0.25);

  /// 深色下边框。
  static const Color borderBottomDark = Color.fromRGBO(255, 255, 255, 0.06);

  /// 投影。
  static const Color shadowLight = Color.fromRGBO(0, 0, 0, 0.06);

  /// 深色投影。
  static const Color shadowDark = Color.fromRGBO(0, 0, 0, 0.4);
}
