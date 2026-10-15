/// 设计 token 守卫。
///
/// **为什么需要它**：样式是唯一没有编译器保护的东西。收敛前全应用出现过
/// 25 种字号（其中 6 个半点值）、9 种临时圆角、19 种间距值，以及 26 个各自
/// 实现的徽标——它们不是一次写坏的，是每次「这里想大一点点」累积出来的。
/// 没有守卫，下一次改动还会这样长回来。
///
/// 这里守三件事：
/// 1. 字号只能来自 [LexiType]；
/// 2. 色板里声明的「文字 × 背景」组合必须满足对比度下限（**算出来**，不是估的）；
/// 3. 音阶自身保持严格递增且不低于可读下限。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

import 'source_scan.dart';

/// 相对亮度（WCAG 2.x）。
double _luminance(Color color) {
  double channel(double v) {
    final c = v;
    return c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// 两个不透明颜色的对比度。
double contrast(Color foreground, Color background) {
  final a = _luminance(foreground);
  final b = _luminance(background);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// 页面底色（浅色）。
const Color _lightSurface = Color(0xFFF2F2F7);

/// 卡片底色（浅色）。
const Color _lightCard = Color(0xFFFFFFFF);

/// 页面底色（深色）。
const Color _darkSurface = Color(0xFF000000);

/// 卡片底色（深色）。
const Color _darkCard = Color(0xFF1C1C1E);

void main() {
  group('字号', () {
    test('lib 里不得出现 fontSize 字面量（token 文件除外）', () {
      final violations = <String>[];
      for (final file in collectDartFiles('lib')) {
        if (file.path.endsWith('ui/theme/lexi_type.dart')) continue;
        for (var i = 0; i < file.lines.length; i += 1) {
          if (RegExp(r'fontSize:\s*[0-9]').hasMatch(file.lines[i])) {
            violations.add(file.locate(i + 1));
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            '字号必须取自 LexiType（`lib/ui/theme/lexi_type.dart`）。\n'
            '收敛前这里有 25 种字号，其中 6 个是半点值——半点值不是设计决定，\n'
            ' 是「这次想大一点点」的临时产物。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });

    test('音阶严格递增且不低于 macOS 可读下限', () {
      final sizes = LexiType.steps.map((s) => s.fontSize!).toList();
      expect(sizes.length, LexiType.steps.length);
      for (var i = 1; i < sizes.length; i += 1) {
        expect(sizes[i], greaterThan(sizes[i - 1]), reason: '音阶必须严格递增：$sizes');
      }
      expect(
        sizes.first,
        greaterThanOrEqualTo(11),
        reason: '最小档不得低于 11（macOS 下限是 10，11 留一档余量）',
      );
    });

    test('每一档都定义了行高', () {
      for (final step in LexiType.steps) {
        expect(
          step.height,
          isNotNull,
          reason: '${step.fontSize} 磅这一档没有行高，多行文本会挤在一起',
        );
      }
    });
  });

  group('对比度', () {
    /// 浅色淡底（`fill` 压在页面底上）的实际颜色。
    final lightFill = Color.alphaBlend(LexiColors.light.fill, _lightSurface);

    /// 断言一组前景色在给定背景上达到 [minRatio]。
    void expectAll(
      Map<String, Color> foregrounds,
      Color background,
      double minRatio, {
      required String where,
      Set<String> except = const <String>{},
    }) {
      foregrounds.forEach((name, color) {
        if (except.contains(name)) return;
        final ratio = contrast(color, background);
        expect(
          ratio,
          greaterThanOrEqualTo(minRatio),
          reason:
              '$name 压在 $where 上只有 ${ratio.toStringAsFixed(2)}:1，'
              ' 低于 $minRatio:1（WCAG AA）',
        );
      });
    }

    test('浅色：四级标签与信号文字在页面底与卡片底上都 ≥4.5:1', () {
      final foregrounds = _textTokens(LexiColors.light);
      expectAll(foregrounds, _lightSurface, 4.5, where: '页面底');
      expectAll(foregrounds, _lightCard, 4.5, where: '卡片底');
    });

    test('浅色：淡底上除 quaternary 外都 ≥4.5:1', () {
      // `quaternaryLabel` 压在 `fill` 上只有约 3.97:1，因此**禁止**这样配对；
      // 淡色底上一律用 tertiary 或更高。这条规则写在这里，不靠人记。
      final light = _textTokens(LexiColors.light)..remove('quaternaryLabel');
      expectAll(light, lightFill, 4.5, where: '淡底(fill)');
      expect(
        contrast(LexiColors.light.quaternaryLabel, lightFill),
        lessThan(4.5),
        reason:
            'quaternaryLabel 在 fill 上不达标——这是**已知且被禁止**的配对，'
            ' 若它忽然达标了，说明色板被改动，请同步更新本条与文档。',
      );
    });

    test('深色：四级标签与信号文字在页面底与卡片底上都 ≥4.5:1', () {
      final foregrounds = _textTokens(LexiColors.dark);
      expectAll(foregrounds, _darkSurface, 4.5, where: '深色页面底');
      expectAll(foregrounds, _darkCard, 4.5, where: '深色卡片底');
    });

    test('四级标签的对比度必须单调递减（层级不能倒挂）', () {
      // 浅色模式原先 tertiary(#AEAEB2, 1.98:1) 比 quaternary(#8E8E93, 2.92:1)
      // 更弱；深色模式原先 secondary(7.31:1) 比 tertiary(9.50:1) 更弱。
      // 两处都是层级倒挂：越「次要」的文字反而越显眼。
      for (final entry in <String, (LexiColors, Color)>{
        '浅色': (LexiColors.light, _lightSurface),
        '深色': (LexiColors.dark, _darkSurface),
      }.entries) {
        final (colors, background) = entry.value;
        final ratios = <double>[
          contrast(colors.label, background),
          contrast(colors.secondaryLabel, background),
          contrast(colors.tertiaryLabel, background),
          contrast(colors.quaternaryLabel, background),
        ];
        for (var i = 1; i < ratios.length; i += 1) {
          expect(
            ratios[i],
            lessThan(ratios[i - 1]),
            reason:
                '${entry.key}模式四级标签的对比度必须递减：'
                '${ratios.map((r) => r.toStringAsFixed(2)).join(" > ")}',
          );
        }
      }
    });

    test('主按钮：白字压强调色 ≥3:1（加粗按钮文字的下限）', () {
      for (final entry in <String, LexiColors>{
        '浅色': LexiColors.light,
        '深色': LexiColors.dark,
      }.entries) {
        final ratio = contrast(Colors.white, entry.value.accent);
        expect(
          ratio,
          greaterThanOrEqualTo(3),
          reason:
              '${entry.key}模式的强调色按钮上白字只有 '
              '${ratio.toStringAsFixed(2)}:1',
        );
      }
    });
  });
}

/// 所有**文字**用色的 token 集合。
///
/// 抽成函数而不是在用例里就地构造：就地写会触发 `prefer_const_declarations`
/// （字面量看着像常量，但字段访问不是常量表达式），而把它写成 `const` 又编不过。
Map<String, Color> _textTokens(LexiColors colors) => <String, Color>{
  'label': colors.label,
  'secondaryLabel': colors.secondaryLabel,
  'tertiaryLabel': colors.tertiaryLabel,
  'quaternaryLabel': colors.quaternaryLabel,
  'accentText': colors.accentText,
  'dangerText': colors.dangerText,
  'successText': colors.successText,
  'warningText': colors.warningText,
  'purpleText': colors.purpleText,
};
