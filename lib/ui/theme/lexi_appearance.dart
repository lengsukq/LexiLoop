/// 界面层的外观模型：把纯 Dart 的设置映射成 Flutter 的 `Color/ThemeMode`。
///
/// 设置模型（`domain/models/app_settings.dart`）不能 import Flutter；
/// 主题层需要 `Color` 与 `ThemeMode`。这一层就是两者的转换点，同时把
/// 「默认值只有一份」这件事收在一处：默认色来自 `core/constants.dart`，
/// 设置模型与主题层都引用它。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/app_settings.dart';

/// 当前外观。
@immutable
class LexiAppearance {
  /// 以主色、次色与模式构造。
  const new({
    required this.primary,
    required this.secondary,
    required this.mode,
  });

  /// 从持久化设置转换。
  // ignore: prefer_constructors_over_static_methods
  static LexiAppearance fromSettings(AppearanceSettings settings) =>
      LexiAppearance(
        primary: Color(settings.primaryColor),
        secondary: Color(settings.secondaryColor),
        mode: switch (settings.mode) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
      );

  /// 主色色种。
  final Color primary;

  /// 次色色种。
  final Color secondary;

  /// 外观模式。
  final ThemeMode mode;

  /// 默认外观（跟随系统 + 薄荷/靛蓝）。
  static final LexiAppearance defaults = LexiAppearance.fromSettings(
    AppearanceSettings.defaults,
  );

  /// 只换模式，保留当前颜色（设置页的分段控件用）。
  LexiAppearance copyWith({
    Color? primary,
    Color? secondary,
    ThemeMode? mode,
  }) => LexiAppearance(
    primary: primary ?? this.primary,
    secondary: secondary ?? this.secondary,
    mode: mode ?? this.mode,
  );

  @override
  bool operator ==(Object other) =>
      other is LexiAppearance &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.mode == mode;

  @override
  int get hashCode => Object.hash(primary, secondary, mode);
}
