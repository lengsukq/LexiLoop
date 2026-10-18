/// LexiLoop 的 `ThemeData` 组装。
///
/// 把 [LexiColors] 与 [LexiTones] 挂到 `ThemeExtension` 上，并据其推导
/// `ColorScheme`，使 Material 组件（对话框、涟漪、输入框、开关、滑条）
/// 也跟随同一套语义色。
///
/// 各组件主题拆成独立构建函数，避免单个 `_build` 膨胀成上帝函数
/// （守卫测试限制函数不超过 40 行）。
library;

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_appearance.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_depth.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/tactile_button_face.dart';

/// 一套外观对应的浅色/深色主题与模式。
@immutable
class LexiThemeBundle {
  /// 以浅色主题、深色主题与模式构造。
  const new({required this.light, required this.dark, required this.mode});

  /// 浅色主题。
  final ThemeData light;

  /// 深色主题。
  final ThemeData dark;

  /// 模式（跟随系统 / 浅色 / 深色）。
  final ThemeMode mode;
}

/// 构建 LexiLoop 的主题。
abstract final class LexiTheme {
  /// 默认外观的浅色主题。
  static final ThemeData light = _build(
    Brightness.light,
    LexiColors.light,
    LexiTones.light,
  );

  /// 默认外观的深色主题。
  static final ThemeData dark = _build(
    Brightness.dark,
    LexiColors.dark,
    LexiTones.dark,
  );

  /// 按用户外观构建一整套主题。
  static LexiThemeBundle build(LexiAppearance appearance) {
    final lightColors = LexiColors.resolve(
      primarySeed: appearance.primary,
      secondarySeed: appearance.secondary,
      brightness: Brightness.light,
    );
    final darkColors = LexiColors.resolve(
      primarySeed: appearance.primary,
      secondarySeed: appearance.secondary,
      brightness: Brightness.dark,
    );
    return LexiThemeBundle(
      light: _build(
        Brightness.light,
        lightColors,
        LexiTones.resolve(colors: lightColors, brightness: Brightness.light),
      ),
      dark: _build(
        Brightness.dark,
        darkColors,
        LexiTones.resolve(colors: darkColors, brightness: Brightness.dark),
      ),
      mode: appearance.mode,
    );
  }

  static ThemeData _build(
    Brightness brightness,
    LexiColors colors,
    LexiTones tones,
  ) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: _colorScheme(brightness, colors),
      scaffoldBackgroundColor: colors.surface,
      extensions: <ThemeExtension<dynamic>>[colors, tones],
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
      outlinedButtonTheme: _outlinedButtonTheme(colors),
      iconButtonTheme: _iconButtonTheme(colors),
      dialogTheme: _dialogTheme(colors),
      bottomSheetTheme: _bottomSheetTheme(colors),
      snackBarTheme: _snackBarTheme(colors),
      progressIndicatorTheme: _progressTheme(colors),
      tooltipTheme: _tooltipTheme(colors),
      iconTheme: IconThemeData(color: colors.secondaryLabel),
      expansionTileTheme: _expansionTheme(colors),
      popupMenuTheme: _popupMenuTheme(colors),
      listTileTheme: _listTileTheme(colors),
      switchTheme: _switchTheme(colors),
      checkboxTheme: _checkboxTheme(colors),
      sliderTheme: _sliderTheme(colors),
      chipTheme: _chipTheme(colors),
      segmentedButtonTheme: _segmentedButtonTheme(colors),
      scrollbarTheme: _scrollbarTheme(colors),
      pageTransitionsTheme: _pageTransitionsTheme(),
    );
  }

  static ExpansionTileThemeData _expansionTheme(LexiColors colors) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LexiRadius.md),
    );
    return ExpansionTileThemeData(
      backgroundColor: colors.fill,
      collapsedBackgroundColor: colors.fill,
      iconColor: colors.secondaryLabel,
      collapsedIconColor: colors.secondaryLabel,
      textColor: colors.label,
      collapsedTextColor: colors.label,
      shape: shape,
      collapsedShape: shape,
      clipBehavior: Clip.antiAlias,
      tilePadding: const EdgeInsets.symmetric(horizontal: LexiSpace.s12),
      childrenPadding: const EdgeInsets.fromLTRB(
        LexiSpace.s12,
        0,
        LexiSpace.s12,
        LexiSpace.s12,
      ),
    );
  }

  static ColorScheme _colorScheme(Brightness brightness, LexiColors colors) {
    return ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: brightness,
    ).copyWith(
      surface: colors.surface,
      onSurface: colors.label,
      surfaceContainerHighest: colors.card,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      primaryContainer: Color.alphaBlend(
        colors.accent.withValues(alpha: LexiTint.tint),
        colors.card,
      ),
      onPrimaryContainer: colors.accentText,
      secondary: colors.secondary,
      onSecondary: colors.onSecondary,
      secondaryContainer: Color.alphaBlend(
        colors.secondary.withValues(alpha: LexiTint.tint),
        colors.card,
      ),
      onSecondaryContainer: colors.secondaryText,
      tertiary: colors.secondaryDeep,
      error: colors.danger,
      onError: colors.onDanger,
      outline: colors.borderDefault,
      outlineVariant: colors.borderSubtle,
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
      fillColor: colors.fill,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s16,
        vertical: LexiSpace.s14,
      ),
      hintStyle: LexiType.body.copyWith(color: colors.tertiaryLabel),
      prefixIconColor: colors.secondaryLabel,
      suffixIconColor: colors.secondaryLabel,
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.borderSubtle),
      ),
      hoverColor: colors.accent.withValues(alpha: LexiTint.subtle),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.danger, width: 2),
      ),
    );
  }

  static FilledButtonThemeData _filledButtonTheme(LexiColors colors) {
    return FilledButtonThemeData(
      style:
          FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: colors.onAccent,
            disabledBackgroundColor: colors.fill,
            disabledForegroundColor: colors.tertiaryLabel,
            padding: const EdgeInsets.symmetric(
              horizontal: LexiSpace.s20,
              vertical: LexiSpace.s12,
            ),
            minimumSize: const Size(0, 48),
            shape: const StadiumBorder(),
            textStyle: LexiType.callout.copyWith(fontWeight: FontWeight.w600),
            shadowColor: colors.accentDeep,
          ).copyWith(
            elevation: WidgetStateProperty.resolveWith(
              (states) =>
                  states.contains(WidgetState.disabled) ||
                      states.contains(WidgetState.pressed)
                  ? 0
                  : 3,
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
        minimumSize: const Size(0, 44),
        shape: const StadiumBorder(),
        textStyle: LexiType.callout.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(LexiColors colors) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.secondaryText,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s20,
          vertical: LexiSpace.s12,
        ),
        shape: const StadiumBorder(),
        side: BorderSide(
          color: colors.secondary.withValues(alpha: LexiTint.border),
        ),
        textStyle: LexiType.callout.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  static IconButtonThemeData _iconButtonTheme(LexiColors colors) {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.secondaryLabel,
        highlightColor: colors.accent.withValues(alpha: LexiTint.tint),
        hoverColor: colors.label.withValues(alpha: LexiTint.group),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LexiRadius.sm),
        ),
      ),
    );
  }

  static DialogThemeData _dialogTheme(LexiColors colors) {
    return DialogThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shadowColor: const Color(0x3316233A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.xl),
      ),
    );
  }

  static BottomSheetThemeData _bottomSheetTheme(LexiColors colors) {
    return BottomSheetThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: colors.card,
      elevation: 0,
      modalElevation: 0,
      dragHandleColor: colors.borderDefault,
      showDragHandle: true,
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
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.lg),
      ),
      insetPadding: const EdgeInsets.all(LexiSpace.s16),
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
        borderRadius: BorderRadius.circular(LexiRadius.xs),
      ),
      textStyle: LexiType.footnote.copyWith(color: colors.card),
    );
  }

  static PopupMenuThemeData _popupMenuTheme(LexiColors colors) {
    return PopupMenuThemeData(
      color: colors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shadowColor: const Color(0x3316233A),
      textStyle: LexiType.body.copyWith(color: colors.label),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.lg),
      ),
    );
  }

  static ListTileThemeData _listTileTheme(LexiColors colors) {
    return ListTileThemeData(
      iconColor: colors.secondaryLabel,
      textColor: colors.label,
      selectedColor: colors.accentText,
      selectedTileColor: colors.accent.withValues(alpha: LexiTint.tint),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s12,
        vertical: LexiSpace.s4,
      ),
    );
  }

  static SwitchThemeData _switchTheme(LexiColors colors) {
    return SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return colors.tertiaryLabel;
        return colors.onAccent;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return colors.fill;
        return states.contains(WidgetState.selected)
            ? colors.accent
            : colors.fill;
      }),
      trackOutlineColor: const WidgetStatePropertyAll<Color>(
        Colors.transparent,
      ),
    );
  }

  static CheckboxThemeData _checkboxTheme(LexiColors colors) {
    return CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return colors.accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStatePropertyAll<Color>(colors.onAccent),
      side: BorderSide(color: colors.borderDefault, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LexiRadius.xs),
      ),
    );
  }

  static SliderThemeData _sliderTheme(LexiColors colors) {
    return SliderThemeData(
      activeTrackColor: colors.accent,
      inactiveTrackColor: colors.fill,
      thumbColor: colors.accent,
      overlayColor: colors.accent.withValues(alpha: LexiTint.tint),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
    );
  }

  static ChipThemeData _chipTheme(LexiColors colors) {
    return ChipThemeData(
      backgroundColor: colors.fill,
      selectedColor: colors.accent.withValues(alpha: LexiTint.tint),
      disabledColor: colors.fill,
      labelStyle: LexiType.footnote.copyWith(color: colors.label),
      secondaryLabelStyle: LexiType.footnote.copyWith(color: colors.accentText),
      checkmarkColor: colors.accentText,
      side: const BorderSide(color: Colors.transparent),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s10,
        vertical: LexiSpace.s6,
      ),
    );
  }

  static SegmentedButtonThemeData _segmentedButtonTheme(LexiColors colors) {
    return SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 44)),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: LexiSpace.s14),
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(color: colors.borderDefault),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.accent.withValues(alpha: LexiTint.tint)
              : Colors.transparent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.accentText
              : colors.secondaryLabel;
        }),
        textStyle: WidgetStatePropertyAll<TextStyle>(
          LexiType.footnote.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static ScrollbarThemeData _scrollbarTheme(LexiColors colors) {
    return ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll<double>(6),
      radius: const Radius.circular(LexiRadius.pill),
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.hovered)
            ? colors.borderStrong
            : colors.borderDefault;
      }),
    );
  }

  static PageTransitionsTheme _pageTransitionsTheme() {
    return const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
      },
    );
  }

  /// 把 Material 的 `TextTheme` 槽位映射到 [LexiType] 的九档。
  ///
  /// **为什么必须显式映射**：不写 `fontSize` 时，每个槽位会用 Material 自带的
  /// 尺寸（labelSmall 11 / labelMedium 12 / bodySmall 12 / labelLarge 14 /
  /// titleSmall 14 / titleMedium 16 / titleLarge 22 / headlineSmall 24 …）。
  /// 于是「全应用只有 9 种字号」这句话在 `textTheme` 这一层就被推翻了——
  /// 而 `fontSize` 守卫看不见这些尺寸，它们长在 Flutter 内部。
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
