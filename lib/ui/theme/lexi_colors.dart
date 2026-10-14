/// LexiLoop 语义色与圆角，对应旧版 `src/app/globals.css` 的设计 token。
///
/// 用 `ThemeExtension` 而非散落的常量，好处是随 `Theme.of(context)` 自动
/// 切换明暗，组件不需要判断当前模式。旧版靠 CSS 变量 + 媒体查询达到同样效果。
library;

import 'package:flutter/material.dart';

/// LexiLoop 的语义色板。
///
/// 取值与旧版 CSS 变量逐条对应，保证视觉一致。
@immutable
class LexiColors extends ThemeExtension<LexiColors> {
  /// 创建一份色板。
  const LexiColors({
    required this.surface,
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
    required this.separator,
    required this.fill,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
  });

  /// 页面底色（`--ll-surface`）。
  final Color surface;

  /// 主文本色（`--ll-label`）。
  final Color label;

  /// 次级文本色（`--ll-secondary-label`）。
  final Color secondaryLabel;

  /// 三级文本色（`--ll-tertiary-label`）。
  final Color tertiaryLabel;

  /// 四级文本色（`--ll-quaternary-label`）。
  final Color quaternaryLabel;

  /// 主强调色（`--ll-accent`，iOS 系统蓝）。
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
    surface: Color(0xFFF2F2F7),
    label: Color(0xFF1C1C1E),
    secondaryLabel: Color(0xFF6E6E73),
    tertiaryLabel: Color(0xFFAEAEB2),
    quaternaryLabel: Color(0xFF8E8E93),
    accent: Color(0xFF007AFF),
    accentDeep: Color(0xFF0040DD),
    danger: Color(0xFFFF3B30),
    dangerDeep: Color(0xFFD70015),
    success: Color(0xFF34C759),
    successDeep: Color(0xFF248A3D),
    warning: Color(0xFFFF9500),
    warningDeep: Color(0xFFC93400),
    purple: Color(0xFFAF52DE),
    purpleDeep: Color(0xFF8944AB),
    separator: Color.fromRGBO(60, 60, 67, 0.12),
    fill: Color.fromRGBO(120, 120, 128, 0.12),
    borderSubtle: Color.fromRGBO(60, 60, 67, 0.08),
    borderDefault: Color.fromRGBO(60, 60, 67, 0.14),
    borderStrong: Color.fromRGBO(60, 60, 67, 0.24),
  );

  /// 深色模式色板。
  static const LexiColors dark = LexiColors(
    surface: Color(0xFF000000),
    label: Color(0xFFF5F5F7),
    secondaryLabel: Color(0xFF98989D),
    tertiaryLabel: Color(0xFFAEAEB2),
    quaternaryLabel: Color(0xFF8E8E93),
    accent: Color(0xFF0A84FF),
    accentDeep: Color(0xFF0A84FF),
    danger: Color(0xFFFF453A),
    dangerDeep: Color(0xFFFF453A),
    success: Color(0xFF30D158),
    successDeep: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    warningDeep: Color(0xFFFF9F0A),
    purple: Color(0xFFBF5AF2),
    purpleDeep: Color(0xFFBF5AF2),
    separator: Color.fromRGBO(84, 84, 88, 0.34),
    fill: Color.fromRGBO(120, 120, 128, 0.24),
    borderSubtle: Color.fromRGBO(255, 255, 255, 0.08),
    borderDefault: Color.fromRGBO(255, 255, 255, 0.14),
    borderStrong: Color.fromRGBO(255, 255, 255, 0.24),
  );

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
    Color? separator,
    Color? fill,
    Color? borderSubtle,
    Color? borderDefault,
    Color? borderStrong,
  }) {
    return LexiColors(
      surface: surface ?? this.surface,
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
  /// 小圆角（10px）——标签、徽章。
  static const double sm = 10;

  /// 中圆角（14px）——输入框、小卡片。
  static const double md = 14;

  /// 大圆角（18px）——卡片。
  static const double lg = 18;

  /// 特大圆角（22px）——浮层、对话框。
  static const double xl = 22;

  /// 最大圆角（28px）——底部 Sheet。
  static const double xxl = 28;
}

/// 读取当前主题色板的便捷扩展。
extension LexiColorsContext on BuildContext {
  /// 当前主题下的 LexiLoop 色板。
  LexiColors get lexiColors => Theme.of(this).extension<LexiColors>()!;
}
