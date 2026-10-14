/// LexiLoop 的 `ThemeData` 组装。
///
/// 把 [LexiColors] 挂到 `ThemeExtension` 上，并据其推导 `ColorScheme`，
/// 使 Material 组件（对话框、涟漪、输入框）也跟随同一套语义色。
///
/// 各组件主题拆成独立构建函数，避免单个 `_build` 膨胀成上帝函数
/// （守卫测试限制函数不超过 40 行）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 构建 LexiLoop 的浅色与深色主题。
abstract final class LexiTheme {
  /// 浅色主题。
  static ThemeData get light => _build(Brightness.light, LexiColors.light);

  /// 深色主题。
  static ThemeData get dark => _build(Brightness.dark, LexiColors.dark);

  static ThemeData _build(Brightness brightness, LexiColors colors) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: _colorScheme(brightness, colors),
      scaffoldBackgroundColor: colors.surface,
      extensions: <ThemeExtension<dynamic>>[colors],
      // 旧版使用系统字体栈（SF Pro / PingFang SC）；Flutter 默认即系统字体，
      // 无需显式指定，保证双端与系统一致。
      visualDensity: VisualDensity.standard,
      splashFactory: isDark
          ? InkSparkle.splashFactory
          : InkRipple.splashFactory,
      dividerTheme: DividerThemeData(
        color: colors.separator,
        thickness: 1,
        space: 1,
      ),
      textTheme: _textTheme(colors),
      appBarTheme: _appBarTheme(colors),
      cardTheme: _cardTheme(isDark),
      inputDecorationTheme: _inputDecorationTheme(colors, isDark),
      filledButtonTheme: _filledButtonTheme(colors),
      textButtonTheme: _textButtonTheme(colors),
      dialogTheme: _dialogTheme(isDark),
      bottomSheetTheme: _bottomSheetTheme(isDark),
      snackBarTheme: _snackBarTheme(isDark),
      progressIndicatorTheme: _progressTheme(colors),
      tooltipTheme: _tooltipTheme(isDark),
    );
  }

  static ColorScheme _colorScheme(Brightness brightness, LexiColors colors) {
    return ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    ).copyWith(
      surface: colors.surface,
      onSurface: colors.label,
      primary: colors.accent,
      onPrimary: Colors.white,
      error: colors.danger,
      outline: colors.borderDefault,
    );
  }

  static AppBarTheme _appBarTheme(LexiColors colors) {
    return AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: colors.label,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    );
  }

  static CardThemeData _cardTheme(bool isDark) {
    return CardThemeData(
      color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.lg),
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(
    LexiColors colors,
    bool isDark,
  ) {
    final radius = BorderRadius.circular(LexiRadius.md);
    return InputDecorationTheme(
      filled: true,
      fillColor: isDark
          ? const Color.fromRGBO(255, 255, 255, 0.05)
          : const Color.fromRGBO(255, 255, 255, 0.7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.danger),
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme(LexiColors colors) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LexiRadius.md),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(LexiColors colors) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    );
  }

  static DialogThemeData _dialogTheme(bool isDark) {
    return DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.xl),
      ),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(bool isDark) {
    return BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(LexiRadius.xxl),
        ),
      ),
    );
  }

  static SnackBarThemeData _snackBarTheme(bool isDark) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark
          ? const Color(0xFF2C2C2E)
          : const Color(0xFF1C1C1E),
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
    );
  }

  static ProgressIndicatorThemeData _progressTheme(LexiColors colors) {
    return ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.fill,
      circularTrackColor: colors.fill,
    );
  }

  static TooltipThemeData _tooltipTheme(bool isDark) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    );
  }

  static TextTheme _textTheme(LexiColors colors) {
    return TextTheme(
      displayLarge: TextStyle(color: colors.label, fontWeight: FontWeight.w700),
      displayMedium: TextStyle(
        color: colors.label,
        fontWeight: FontWeight.w700,
      ),
      displaySmall: TextStyle(color: colors.label, fontWeight: FontWeight.w700),
      headlineLarge: TextStyle(
        color: colors.label,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: TextStyle(
        color: colors.label,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: TextStyle(
        color: colors.label,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(color: colors.label, fontWeight: FontWeight.w600),
      titleMedium: TextStyle(color: colors.label, fontWeight: FontWeight.w600),
      titleSmall: TextStyle(color: colors.label, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(color: colors.label),
      bodyMedium: TextStyle(color: colors.label),
      bodySmall: TextStyle(color: colors.secondaryLabel),
      labelLarge: TextStyle(color: colors.label, fontWeight: FontWeight.w600),
      labelMedium: TextStyle(color: colors.secondaryLabel),
      labelSmall: TextStyle(color: colors.tertiaryLabel),
    );
  }
}
