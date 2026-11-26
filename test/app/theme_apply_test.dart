/// 外观设置 → 主题包的接线测试。
///
/// 这里验证的是「改设置真的会改 MaterialApp 的三样东西」：浅色主题、
/// 深色主题与模式。具体色值推导在 `test/ui/theme_palette_test.dart`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/theme_providers.dart';

void main() {
  ProviderContainer containerFor(AppSettings settings) {
    final container = ProviderContainer(
      overrides: <Override>[
        appSettingsProvider.overrideWith((ref) async => settings),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('默认设置得到跟随系统与默认配色', () async {
    final container = containerFor(AppSettings.defaults);
    await container.read(appSettingsProvider.future);

    final bundle = container.read(themeBundleProvider);
    expect(bundle.mode, ThemeMode.system);
    expect(
      bundle.light.extension<LexiColors>()!.accent,
      LexiColors.light.accent,
    );
  });

  test('深色模式与自定义主/次色进入主题包', () async {
    final settings = appSettingsFromRaw(<String, Object?>{
      'themeMode': 'dark',
      'themePrimaryColor': 0xFF0A84FF,
      'themeSecondaryColor': 0xFFFF2D55,
    });
    final container = containerFor(settings);
    await container.read(appSettingsProvider.future);

    final bundle = container.read(themeBundleProvider);
    expect(bundle.mode, ThemeMode.dark);
    final light = bundle.light.extension<LexiColors>()!;
    expect(light.accent, isNot(LexiColors.light.accent));
    expect(light.secondary, isNot(LexiColors.light.secondary));
  });

  test('未知模式与坏颜色不会让主题构建失败', () async {
    final settings = appSettingsFromRaw(<String, Object?>{
      'themeMode': 'sepia',
      'themePrimaryColor': 'blue',
    });
    final container = containerFor(settings);
    await container.read(appSettingsProvider.future);

    final bundle = container.read(themeBundleProvider);
    expect(bundle.mode, ThemeMode.system);
    expect(
      bundle.light.extension<LexiColors>()!.accent,
      LexiColors.light.accent,
    );
  });
}
