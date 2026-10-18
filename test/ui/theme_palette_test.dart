/// 主题色推导的对比度守卫。
///
/// **为什么不能只测默认色**：主色是用户选的，任何一个预设或极端自定义色
/// 都必须保证「正文可读、按钮上的文字可读」。这里把 12 个预设 × 明暗两套
/// 全部算一遍，并额外用白/黑/灰/黄四种极端色种压一遍。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_palette.dart';
import 'package:lexiloop/ui/theme/lexi_tones.dart';

import '../support/contrast.dart';

/// 除强调色以外的文字 token。
List<Color> _fixedText(LexiColors colors) => <Color>[
  colors.label,
  colors.secondaryLabel,
  colors.tertiaryLabel,
  colors.quaternaryLabel,
  colors.dangerText,
  colors.successText,
  colors.warningText,
  colors.purpleText,
];

/// 全部文字 token（含随主题变化的强调/次色文字）。
List<Color> _allText(LexiColors colors) => <Color>[
  ..._fixedText(colors),
  colors.accentText,
  colors.secondaryText,
];

/// 带名字的文字 token，便于失败时指出是哪一级。
Map<String, Color> _namedText(LexiColors colors) => <String, Color>{
  'label': colors.label,
  'secondaryLabel': colors.secondaryLabel,
  'tertiaryLabel': colors.tertiaryLabel,
  'quaternaryLabel': colors.quaternaryLabel,
  'dangerText': colors.dangerText,
  'successText': colors.successText,
  'warningText': colors.warningText,
  'purpleText': colors.purpleText,
  'accentText': colors.accentText,
  'secondaryText': colors.secondaryText,
};

void main() {
  group('预设色种', () {
    for (final preset in LexiPalette.presets) {
      test('${preset.label} 在明暗两套下都可读', () {
        for (final brightness in Brightness.values) {
          final colors = LexiColors.resolve(
            primarySeed: preset.color,
            secondarySeed: const Color(defaultThemeSecondaryColor),
            brightness: brightness,
          );
          final tones = LexiTones.resolve(
            colors: colors,
            brightness: brightness,
          );
          final fillOverCard = Color.alphaBlend(colors.fill, colors.card);
          final fillOverSurface = Color.alphaBlend(colors.fill, colors.surface);
          for (final background in <Color>[
            colors.surface,
            colors.card,
            fillOverCard,
            fillOverSurface,
          ]) {
            for (final entry in _namedText(colors).entries) {
              final ratio = contrastRatio(entry.value, background);
              expect(
                ratio,
                greaterThanOrEqualTo(4.5),
                reason:
                    '$brightness / ${preset.label} / ${entry.key}：'
                    '${ratio.toStringAsFixed(2)}:1',
              );
            }
          }
          expect(
            contrastRatio(colors.onAccent, colors.accent),
            greaterThanOrEqualTo(4.5),
            reason: '${preset.label} 的按钮文字',
          );
          expect(
            contrastRatio(colors.onSecondary, colors.secondary),
            greaterThanOrEqualTo(4.5),
            reason: '${preset.label} 的次色按钮文字',
          );
          expect(
            contrastRatio(colors.onDanger, colors.danger),
            greaterThanOrEqualTo(4.5),
            reason: '${preset.label} 的危险按钮文字',
          );
          for (final tone in LexiTone.values) {
            final style = tones.styleOf(tone);
            for (final foreground in <Color>[
              ..._allText(colors),
              style.foreground,
            ]) {
              final ratio = contrastRatio(foreground, style.background);
              expect(
                ratio,
                greaterThanOrEqualTo(4.5),
                reason:
                    '$brightness / ${preset.label} / $tone：'
                    '${ratio.toStringAsFixed(2)}:1',
              );
            }
          }
        }
      });
    }
  });

  group('极端色种', () {
    const extremes = <String, Color>{
      '白': Color(0xFFFFFFFF),
      '黑': Color(0xFF000000),
      '灰': Color(0xFF8E8E93),
      '黄': Color(0xFFFFCC00),
    };
    for (final entry in extremes.entries) {
      test('${entry.key} 作为主色仍可读', () {
        for (final brightness in Brightness.values) {
          final colors = LexiColors.resolve(
            primarySeed: entry.value,
            secondarySeed: entry.value,
            brightness: brightness,
          );
          expect(
            contrastRatio(colors.onAccent, colors.accent),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(colors.accentText, colors.card),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrastRatio(colors.secondaryText, colors.surface),
            greaterThanOrEqualTo(4.5),
          );
        }
      });
    }
  });

  test('相同色种得到相同色板', () {
    final first = LexiColors.resolve(
      primarySeed: const Color(defaultThemePrimaryColor),
      secondarySeed: const Color(defaultThemeSecondaryColor),
      brightness: Brightness.light,
    );
    final second = LexiColors.resolve(
      primarySeed: const Color(defaultThemePrimaryColor),
      secondarySeed: const Color(defaultThemeSecondaryColor),
      brightness: Brightness.light,
    );
    expect(first.accent, second.accent);
    expect(first.accentText, second.accentText);
    expect(first.secondary, second.secondary);
  });
}
