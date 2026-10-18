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
import 'package:lexiloop/ui/theme/lexi_depth.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/tactile_button_face.dart';

/// 构建 LexiLoop 的浅色与深色主题。
abstract final class LexiTheme {
  /// 浅色主题。
  static ThemeData get light => _build(Brightness.light, LexiColors.light);

  /// 深色主题。
  static ThemeData get dark => _build(Brightness.dark, LexiColors.dark);

  static ThemeData _build(Brightness brightness, LexiColors colors) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: _colorScheme(brightness, colors),
      scaffoldBackgroundColor: colors.surface,
      extensions: <ThemeExtension<dynamic>>[colors],
      // 旧版使用系统字体栈（SF Pro / PingFang SC）；Flutter 默认即系统字体，
      // 无需显式指定，保证双端与系统一致。
      visualDensity: VisualDensity.standard,
      splashFactory: InkRipple.splashFactory,
      // 键盘焦点与 hover 的底色。
      //
      // 桌面端（macOS）用户会大量用键盘，`focusColor` 是唯一的焦点提示；
      // HIG 的 `focus-and-selection.md` 要求焦点必须清晰可见且不依赖颜色
      // 单独表意，所以这里给的是 accent 的淡底 + 组件自身的 focus ring。
      focusColor: colors.accent.withValues(alpha: LexiTint.tint),
      hoverColor: colors.label.withValues(alpha: LexiTint.group),
      dividerTheme: DividerThemeData(
        color: colors.separator,
        thickness: 1,
        space: 1,
      ),
      textTheme: _textTheme(colors),
      appBarTheme: _appBarTheme(colors),
      cardTheme: _cardTheme(colors),
      inputDecorationTheme: _inputDecorationTheme(colors),
      filledButtonTheme: _filledButtonTheme(colors),
      textButtonTheme: _textButtonTheme(colors),
      dialogTheme: _dialogTheme(colors),
      bottomSheetTheme: _bottomSheetTheme(colors),
      snackBarTheme: _snackBarTheme(colors),
      progressIndicatorTheme: _progressTheme(colors),
      tooltipTheme: _tooltipTheme(colors),
      iconTheme: IconThemeData(color: colors.secondaryLabel),
      expansionTileTheme: _expansionTheme(colors),
    );
  }

  static ExpansionTileThemeData _expansionTheme(LexiColors colors) =>
      ExpansionTileThemeData(
        iconColor: colors.secondaryLabel,
        collapsedIconColor: colors.secondaryLabel,
        textColor: colors.label,
        collapsedTextColor: colors.label,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: EdgeInsets.zero,
      );

  static ColorScheme _colorScheme(Brightness brightness, LexiColors colors) {
    return ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    ).copyWith(
      surface: colors.surface,
      onSurface: colors.label,
      surfaceContainerHighest: colors.card,
      secondary: colors.accentText,
      onSecondary: colors.card,
      secondaryContainer: Color.alphaBlend(
        colors.accent.withValues(alpha: LexiTint.tint),
        colors.card,
      ),
      onSecondaryContainer: colors.accentText,
      primary: colors.accentText,
      onPrimary: colors.card,
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

  static CardThemeData _cardTheme(LexiColors colors) {
    return CardThemeData(
      color: colors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.lg),
      ),
    );
  }

  static InputDecorationTheme _inputDecorationTheme(LexiColors colors) {
    final radius = BorderRadius.circular(LexiRadius.md);
    return InputDecorationTheme(
      filled: true,
      fillColor: colors.card,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s16,
        vertical: LexiSpace.s12,
      ),
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
      style:
          FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s20,
              vertical: LexiSpace.s14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(LexiRadius.md),
            ),
            textStyle: LexiType.callout.copyWith(fontWeight: FontWeight.w600),
            shadowColor: LexiDepth.buttonShadow,
          ).copyWith(
            elevation: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ||
                      states.contains(WidgetState.pressed)
                  ? 0
                  : 2,
            ),
            animationDuration: LexiDepth.press,
            backgroundBuilder: (context, states, child) =>
                TactileButtonFace(states: states, child: child),
          ),
    );
  }

  static TextButtonThemeData _textButtonTheme(LexiColors colors) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accentText,
        textStyle: LexiType.callout.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  static DialogThemeData _dialogTheme(LexiColors colors) {
    return DialogThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: LexiDepth.buttonShadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.xl),
      ),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(LexiColors colors) {
    return BottomSheetThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(LexiRadius.xxl),
        ),
      ),
    );
  }

  static SnackBarThemeData _snackBarTheme(LexiColors colors) {
    return SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.label,
      contentTextStyle: LexiType.callout.copyWith(color: colors.card),
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

  static TooltipThemeData _tooltipTheme(LexiColors colors) {
    return TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.label,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      textStyle: LexiType.footnote.copyWith(color: colors.card),
    );
  }

  /// 把 Material 的 `TextTheme` 槽位映射到 [LexiType] 的九档。
  ///
  /// **为什么必须显式映射**：不写 `fontSize` 时，每个槽位会用 Material 自带的
  /// 尺寸（labelSmall 11 / labelMedium 12 / bodySmall 12 / labelLarge 14 /
  /// titleSmall 14 / titleMedium 16 / titleLarge 22 / headlineSmall 24 …）。
  /// 于是「全应用只有 9 种字号」这句话在 `textTheme` 这一层就被推翻了——
  /// 而 `fontSize` 守卫看不见这些尺寸，它们长在 Flutter 内部。
  ///
  /// 这里按**角色**对齐，不按尺寸硬凑：display 系列归 `hero`，headline 系列
  /// 逐级落到 `display`/`page`/`title2`，title 系列落到 `title`，body 与
  /// label 落到 `body`/`callout`/`footnote`/`caption`。
  static TextTheme _textTheme(LexiColors colors) {
    return TextTheme(
      displayLarge: LexiType.hero.copyWith(color: colors.label),
      displayMedium: LexiType.hero.copyWith(color: colors.label),
      displaySmall: LexiType.hero.copyWith(color: colors.label),
      headlineLarge: LexiType.display.copyWith(color: colors.label),
      headlineMedium: LexiType.page.copyWith(color: colors.label),
      headlineSmall: LexiType.title2.copyWith(color: colors.label),
      titleLarge: LexiType.title2.copyWith(color: colors.label),
      titleMedium: LexiType.title.copyWith(color: colors.label),
      titleSmall: LexiType.callout.copyWith(color: colors.label),
      bodyLarge: LexiType.callout.copyWith(color: colors.label),
      bodyMedium: LexiType.body.copyWith(color: colors.label),
      bodySmall: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      labelLarge: LexiType.callout.copyWith(color: colors.label),
      labelMedium: LexiType.footnote.copyWith(color: colors.secondaryLabel),
      labelSmall: LexiType.caption.copyWith(color: colors.tertiaryLabel),
    );
  }
}
