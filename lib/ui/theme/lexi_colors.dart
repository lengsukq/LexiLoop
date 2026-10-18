/// LexiLoop 的语义色与圆角：清透蓝底、鲜绿主色与柔和彩色分区。
///
/// 用 `ThemeExtension` 而非散落的常量，好处是随 `Theme.of(context)` 自动
/// 切换明暗，组件不需要判断当前模式。旧版靠 CSS 变量 + 媒体查询达到同样效果。
library;

import 'package:flutter/material.dart';

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
    required this.danger,
    required this.dangerDeep,
    required this.success,
    required this.successDeep,
    required this.warning,
    required this.warningDeep,
    required this.purple,
    required this.purpleDeep,
    required this.accentText,
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
  /// 浅色用纯白、深色用 `#1C1C1E`：卡片必须与页面底拉开一档，否则发丝
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

  /// 主强调色：鲜绿，用于主动作、选中和进度。
  final Color accent;

  /// 强调色的深色变体（`--ll-accent-deep`）。
  final Color accentDeep;

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

  /// 紫色强调（`--ll-purple`）。
  final Color purple;

  /// 紫色深色变体（`--ll-purple-deep`）。
  final Color purpleDeep;

  /// 强调色作为**文字**时的取值。
  ///
  /// 饱和的 [accent] 只适合做填充、圆点与进度条：它当文字压在浅色底上只有
  /// 3.2–3.6:1，达不到 4.5:1。这一组是专供文字的深色变体，在页面底
  /// （`surface`）、卡片底（白）与淡色底（`fill`）上都 ≥4.5:1。
  final Color accentText;

  /// 危险色作为文字时的取值。
  final Color dangerText;

  /// 成功色作为文字时的取值。
  ///
  /// 浅色下 [success] 当文字只有 1.99:1——这是整套色板里最严重的一处，
  /// 所以它必须有一份独立的文字色。
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

  /// 浅色模式色板。
  static const LexiColors light = LexiColors(
    surface: Color(0xFFF3F6FC),
    card: Color(0xFFFFFFFF),
    label: Color(0xFF252B3B),
    // 四级标签按「对比度单调递减」取值，且**每一级都 ≥4.5:1**。
    // 原先 tertiary(#AEAEB2, 1.98:1) 比 quaternary(#8E8E93, 2.92:1) 更弱，
    // 层级是反的，而且两级都读不清——它们被用在禁用按钮、提示与
    // `labelSmall` 上，那些都是要读的文字。
    secondaryLabel: Color(0xFF586275),
    tertiaryLabel: Color(0xFF60697A),
    quaternaryLabel: Color(0xFF626A7A),
    accent: Color(0xFF35C989),
    accentDeep: Color(0xFF146C4B),
    danger: Color(0xFFFF3B30),
    dangerDeep: Color(0xFFD70015),
    success: Color(0xFF49816A),
    successDeep: Color(0xFF248A3D),
    warning: Color(0xFFFF9500),
    warningDeep: Color(0xFFC93400),
    purple: Color(0xFFAF52DE),
    purpleDeep: Color(0xFF8944AB),
    accentText: Color(0xFF146C4B),
    dangerText: Color(0xFFC2140F),
    successText: Color(0xFF146B31),
    warningText: Color(0xFF8A5200),
    purpleText: Color(0xFF7A3B99),
    separator: Color.fromRGBO(60, 60, 67, 0.12),
    fill: Color.fromRGBO(78, 116, 173, 0.08),
    borderSubtle: Color.fromRGBO(60, 60, 67, 0.08),
    borderDefault: Color.fromRGBO(60, 60, 67, 0.14),
    borderStrong: Color.fromRGBO(60, 60, 67, 0.24),
  );

  /// 深色模式色板。
  static const LexiColors dark = LexiColors(
    surface: Color(0xFF171D2B),
    card: Color(0xFF232D3F),
    label: Color(0xFFE8EDF7),
    secondaryLabel: Color(0xFFAFBACC),
    tertiaryLabel: Color(0xFFA3AFC2),
    quaternaryLabel: Color(0xFF9AA6BA),
    accent: Color(0xFF66DCA8),
    accentDeep: Color(0xFF66DCA8),
    danger: Color(0xFFFF453A),
    dangerDeep: Color(0xFFFF453A),
    success: Color(0xFF91C9AE),
    successDeep: Color(0xFF91C9AE),
    warning: Color(0xFFFF9F0A),
    warningDeep: Color(0xFFFF9F0A),
    purple: Color(0xFFBF5AF2),
    purpleDeep: Color(0xFFBF5AF2),
    // 深色底上饱和色本身就 ≥4.6:1（黑底与 #1C1C1E 卡片底都过），
    // 因此文字色与填充色同值，不需要再深一档。
    accentText: Color(0xFF66DCA8),
    dangerText: Color(0xFFFFA198),
    successText: Color(0xFF91C9AE),
    warningText: Color(0xFFFF9F0A),
    purpleText: Color(0xFFD6ADE8),
    separator: Color.fromRGBO(84, 84, 88, 0.34),
    fill: Color.fromRGBO(120, 120, 128, 0.24),
    borderSubtle: Color.fromRGBO(255, 255, 255, 0.08),
    borderDefault: Color.fromRGBO(255, 255, 255, 0.14),
    borderStrong: Color.fromRGBO(255, 255, 255, 0.24),
  );

  /// 强调色上的文字；浅色白字，深色使用深底文字。
  Color get onAccent =>
      accent.computeLuminance() > 0.3 ? const Color(0xFF143B2B) : Colors.white;

  @override
  LexiColors copyWith({
    Color? surface,
    Color? label,
    Color? secondaryLabel,
    Color? tertiaryLabel,
    Color? quaternaryLabel,
    Color? accent,
    Color? accentDeep,
    Color? danger,
    Color? dangerDeep,
    Color? success,
    Color? successDeep,
    Color? warning,
    Color? warningDeep,
    Color? purple,
    Color? purpleDeep,
    Color? accentText,
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
      danger: danger ?? this.danger,
      dangerDeep: dangerDeep ?? this.dangerDeep,
      success: success ?? this.success,
      successDeep: successDeep ?? this.successDeep,
      warning: warning ?? this.warning,
      warningDeep: warningDeep ?? this.warningDeep,
      purple: purple ?? this.purple,
      purpleDeep: purpleDeep ?? this.purpleDeep,
      accentText: accentText ?? this.accentText,
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
      danger: Color.lerp(danger, other.danger, t)!,
      dangerDeep: Color.lerp(dangerDeep, other.dangerDeep, t)!,
      success: Color.lerp(success, other.success, t)!,
      successDeep: Color.lerp(successDeep, other.successDeep, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningDeep: Color.lerp(warningDeep, other.warningDeep, t)!,
      purple: Color.lerp(purple, other.purple, t)!,
      purpleDeep: Color.lerp(purpleDeep, other.purpleDeep, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
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

/// LexiLoop 的圆角档位，对应旧版 CSS 的 `--radius-*`。
abstract final class LexiRadius {
  /// 微型圆角（4px）——热力图小方块、行内 diff 标签。
  ///
  /// 只给边长 12～16 的微型元素用；再大就该走 [xs] 以上。
  static const double xxs = 4;

  /// 极小圆角（6px）——内嵌的小标签、输入框内的色块。
  static const double xs = 6;

  /// 小圆角（10px）——标签、徽章。
  static const double sm = 10;

  /// 中圆角（14px）——输入框、小卡片。
  static const double md = 16;

  /// 大圆角（18px）——卡片。
  static const double lg = 20;

  /// 特大圆角（22px）——浮层、对话框。
  static const double xl = 24;

  /// 最大圆角（28px）——底部 Sheet。
  static const double xxl = 28;

  /// 胶囊圆角——计数胶囊、筛选 chip。
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
/// 功能层采用中性高光与灰绿深底，集中定义避免散落在构建逻辑里，
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
