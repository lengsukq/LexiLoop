/// 主题层把 Material 的 `TextTheme` 接到 [LexiType] 上。
///
/// **为什么需要它**：`fontSize` 守卫只看得见 `lib` 里的字面量，看不见
/// Material 自带的尺寸。不显式映射槽位时，`Theme.of(context).textTheme.X`
/// 会用 labelSmall 11 / labelMedium 12 / bodySmall 12 / labelLarge 14 /
/// titleSmall 14 / titleMedium 16 / titleLarge 22 / headlineSmall 24 —— 全应用
/// 75 处这样取值，于是「只有 9 种字号」在主题层就被推翻了，而静态守卫
/// 一声不吭。
///
/// 这里断言每个槽位解析出来的 `fontSize` 都落在 [LexiType.steps] 里，
/// 并且都带上了颜色（否则会退化成 Flutter 的默认黑/白，深色下读不清）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 取 [TextTheme] 的全部槽位。
List<TextStyle?> slots(TextTheme theme) => <TextStyle?>[
  theme.displayLarge,
  theme.displayMedium,
  theme.displaySmall,
  theme.headlineLarge,
  theme.headlineMedium,
  theme.headlineSmall,
  theme.titleLarge,
  theme.titleMedium,
  theme.titleSmall,
  theme.bodyLarge,
  theme.bodyMedium,
  theme.bodySmall,
  theme.labelLarge,
  theme.labelMedium,
  theme.labelSmall,
];

void main() {
  final allowed = LexiType.steps.map((s) => s.fontSize).toSet();

  for (final (String mode, ThemeData theme) in <(String, ThemeData)>[
    ('浅色', LexiTheme.light),
    ('深色', LexiTheme.dark),
  ]) {
    group(mode, () {
      test('每个 TextTheme 槽位的字号都来自 LexiType', () {
        for (final slot in slots(theme.textTheme)) {
          expect(slot, isNotNull);
          expect(
            slot!.fontSize,
            isNotNull,
            reason: '有槽位没写 fontSize，会退回 Material 自带尺寸',
          );
          expect(
            allowed,
            contains(slot.fontSize),
            reason:
                '字号 ${slot.fontSize} 不在 LexiType 音阶 $allowed 里。\n'
                'Material 的默认尺寸（11/12/14/16/22/24…）会从这里漏进界面，\n'
                '而 fontSize 守卫看不见它们。',
          );
        }
      });

      test('每个 TextTheme 槽位都带上了颜色', () {
        for (final slot in slots(theme.textTheme)) {
          expect(
            slot!.color,
            isNotNull,
            reason: '没写颜色的槽位会用 Flutter 默认色，深色模式下读不清',
          );
        }
      });

      test('每个槽位都带上了行高', () {
        for (final slot in slots(theme.textTheme)) {
          expect(slot!.height, isNotNull, reason: '没写行高的槽位，多行文本会挤在一起');
        }
      });
    });
  }

  test('焦点与 hover 底色来自 LexiTint', () {
    // 桌面端靠键盘导航，focusColor 是唯一的焦点提示，不能为空。
    expect(LexiTheme.light.focusColor.a, greaterThan(0));
    expect(LexiTheme.light.hoverColor.a, greaterThan(0));
    expect(LexiTheme.dark.focusColor.a, greaterThan(0));
    expect(LexiTheme.dark.hoverColor.a, greaterThan(0));
  });
}
