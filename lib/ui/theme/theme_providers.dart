/// 外观 provider：把设置流转换成主题包。
///
/// **为什么是 Provider 而不是在 `LexiLoopApp` 里直接读设置**：
/// `MaterialApp.router` 需要同时拿到浅色、深色与模式三样；把它们算在一个
/// provider 里，设置变化时只重建一次，不会让 `MaterialApp` 在一次构建里
/// 反复推导色板（每次推导都要跑一遍对比度收敛）。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/ui/theme/lexi_appearance.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

/// 当前外观。
///
/// 设置尚未加载完成时用默认外观；`AsyncValue.value` 在刷新期间会保留上一次
/// 的值，所以改主题不会先闪一下默认色。
final Provider<LexiAppearance> appearanceProvider = Provider<LexiAppearance>((
  ref,
) {
  final settings = ref.watch(appSettingsProvider).value;
  return LexiAppearance.fromSettings(
    settings?.appearance ?? AppearanceSettings.defaults,
  );
});

/// 当前外观对应的浅色/深色主题与模式。
final Provider<LexiThemeBundle> themeBundleProvider = Provider<LexiThemeBundle>(
  (ref) => LexiTheme.build(ref.watch(appearanceProvider)),
);
