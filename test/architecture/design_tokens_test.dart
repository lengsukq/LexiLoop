/// 设计 token 守卫。
///
/// **为什么需要它**：样式是唯一没有编译器保护的东西。收敛前全应用出现过
/// 25 种字号（其中 6 个半点值）、9 种临时圆角、19 种间距值，以及 26 个各自
/// 实现的徽标——它们不是一次写坏的，是每次「这里想大一点点」累积出来的。
/// 没有守卫，下一次改动还会这样长回来。
///
/// 这里守五件事：
/// 1. 字号只能来自 [LexiType]；
/// 2. 圆角只能来自 [LexiRadius]；
/// 3. 间距必须落在 [LexiSpace] 音阶上；
/// 4. 色板里声明的「文字 × 背景」组合必须满足对比度下限（**算出来**，不是估的）；
/// 5. 音阶自身保持严格递增且不低于可读下限。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

import '../support/contrast.dart';
import 'source_scan.dart';

/// 页面底色（浅色）。
const Color _lightSurface = Color(0xFFF2F2F7);

/// 卡片底色（浅色）。
const Color _lightCard = Color(0xFFFFFFFF);

/// 页面底色（深色）。
const Color _darkSurface = Color(0xFF000000);

/// 卡片底色（深色）。
const Color _darkCard = Color(0xFF1C1C1E);

/// 允许使用 `LiquidGlass` 的**功能层**文件。
///
/// 每一个都是「浮在内容之上的界面构件」：桌面侧边栏、底部 Tab Bar、
/// 「更多」底部 Sheet、筛选 Sheet、初始化配置对话框、批量操作浮条。
/// 内容层的卡片一律走 `Surface`。
const Set<String> functionalLayerFiles = <String>{
  'lib/ui/adaptive_shell.dart',
  'lib/features/words/widgets/word_filter_sheet.dart',
  'lib/features/initialize/configurator/initialization_configurator.dart',
  'lib/features/initialize/widgets/queue_bulk_bar.dart',
};

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

  group('圆角', () {
    test('lib 里不得出现 circular 的数字字面量', () {
      final violations = <String>[];
      final pattern = RegExp(r'(?:BorderRadius|Radius)\.circular\(\s*[0-9]');
      for (final file in collectDartFiles('lib')) {
        for (var i = 0; i < file.lines.length; i += 1) {
          if (pattern.hasMatch(file.lines[i])) {
            violations.add(file.locate(i + 1));
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            '圆角必须取自 LexiRadius（`lib/ui/theme/lexi_colors.dart`）。\n'
            '收敛前这里有 9 种临时圆角（3/4/6/8/10/12/13/14/16/999）：\n'
            '同一个应用里同时出现 13 与 14 两种「差不多」的圆角，是纯噪声。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });

    test('圆角档位严格递增且不低于 4', () {
      const steps = LexiRadius.steps;
      expect(steps.length, greaterThanOrEqualTo(6));
      for (var i = 1; i < steps.length; i += 1) {
        expect(
          steps[i],
          greaterThan(steps[i - 1]),
          reason: '圆角档位必须严格递增：$steps',
        );
      }
      expect(
        steps.first,
        greaterThanOrEqualTo(4),
        reason: '最小档不得低于 4——再小就看不出来了',
      );
      expect(
        LexiRadius.pill,
        greaterThan(steps.last),
        reason: 'pill 是形状哨兵，必须大于所有真实档位',
      );
    });
  });

  group('间距', () {
    test('lib 里的间距必须落在 LexiSpace 音阶上', () {
      final violations = <String>[];
      for (final file in collectDartFiles('lib')) {
        violations.addAll(_spacingViolations(file));
      }
      expect(
        violations,
        isEmpty,
        reason:
            '间距必须取自 LexiSpace（`lib/ui/theme/lexi_space.dart`）。\n'
            '收敛前这里有 25 种间距值（1 / 2.5 / 3 / 5 / 7 / 9 / 18 / 22 …），\n'
            '差一两个像素在单屏上看不出来，但同一列卡片之间「有的差 12、\n'
            '有的差 14」会让人说不出哪里别扭。\n'
            '固定尺寸（列宽、点击热区）不是间距，就地命名成有语义的 const。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });

    test('间距音阶是严格递增的 2pt 节奏', () {
      const steps = LexiSpace.steps;
      for (var i = 1; i < steps.length; i += 1) {
        expect(
          steps[i],
          greaterThan(steps[i - 1]),
          reason: '间距音阶必须严格递增：$steps',
        );
      }
      for (final step in steps) {
        expect(step % 2, 0, reason: '$step 不在 2pt 节奏上');
      }
    });
  });

  group('材质', () {
    test('LiquidGlass 只能出现在功能层', () {
      final violations = <String>[];
      for (final file in collectDartFiles('lib')) {
        if (functionalLayerFiles.contains(file.path)) continue;
        for (var i = 0; i < file.lines.length; i += 1) {
          if (file.lines[i].contains('LiquidGlass(')) {
            violations.add(file.locate(i + 1));
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'Liquid Glass 只属于**功能层**（侧边栏、底部栏、弹窗、浮层操作条）。\n'
            "Apple `materials.md` 的原话是「Don't use Liquid Glass in the "
            'content layer… use standard materials for elements in the content '
            'layer」。玻璃压在玻璃上会让所有卡片落在同一层材质上，层级只能\n'
            '靠间距硬撑——这正是界面「看起来不统一」的根源。\n'
            '内容层请用 Surface（`lib/ui/widgets/surface.dart`）。\n'
            '违规项：\n${violations.join('\n')}',
      );
    });
  });

  group('淡色透明度', () {
    test('lib 里不得出现 withValues(alpha: 数字)（token 文件除外）', () {
      final violations = <String>[];
      final pattern = RegExp(r'withValues\(alpha:\s*[0-9]');
      for (final file in collectDartFiles('lib')) {
        if (file.path == 'lib/ui/theme/lexi_tint.dart') continue;
        for (var i = 0; i < file.lines.length; i += 1) {
          if (pattern.hasMatch(file.lines[i])) {
            violations.add(file.locate(i + 1));
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            '淡色透明度必须取自 LexiTint（`lib/ui/theme/lexi_tint.dart`）。\n'
            '收敛前这里有 21 种取值：0.06 / 0.07 / 0.08 三档同时存在，\n'
            '0.10 / 0.12 / 0.14 / 0.15 / 0.16 五档同时存在，描边散在\n'
            '0.2 / 0.25 / 0.3 / 0.35。肉眼读不出 12% 与 14% 的差别，\n'
            '只觉得「哪里不一致」——那正是这次要收掉的噪声。\n'
            '违规项：\n${violations.join('\n')}',
      );
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
        final ratio = contrastRatio(color, background);
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
        contrastRatio(LexiColors.light.quaternaryLabel, lightFill),
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
          contrastRatio(colors.label, background),
          contrastRatio(colors.secondaryLabel, background),
          contrastRatio(colors.tertiaryLabel, background),
          contrastRatio(colors.quaternaryLabel, background),
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
        final ratio = contrastRatio(Colors.white, entry.value.accent);
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

/// 找出 [file] 中间距不在 [LexiSpace] 音阶上的地方。
///
/// 扫描是启发式的，只看两个「间距一定住在这里」的位置：
/// * `EdgeInsets.*(...)`——取到最近的 `)`，`dart format` 不会在参数里嵌调用；
/// * `SizedBox(width: …)` / `SizedBox(height: …)`——只看这两个具名参数，
///   因此 `child:` 里的数字（`Text('…', maxLines: 2)`）不会被误判。
///
/// 反过来说，写在别的参数里的间距（`BoxConstraints(minHeight:)` 之类）这里
/// 管不到——那些是**尺寸**而不是间距，本就该用有语义的常量表达。
List<String> _spacingViolations(SourceFile file) {
  final text = file.lines.join('\n');
  final violations = <String>[];

  int lineOf(int offset) =>
      '\n'.allMatches(text.substring(0, offset)).length + 1;

  void check(num value, int offset, String where) {
    if (value == 0) return;
    if (LexiSpace.steps.contains(value.toDouble())) return;
    violations.add('${file.path}:${lineOf(offset)}  $where 里的 $value 不在音阶上');
  }

  final numbers = RegExp(r'[0-9]+(?:\.[0-9]+)?');

  for (final match in RegExp(
    r'EdgeInsets[A-Za-z.]*\(([^()]*)\)',
    dotAll: true,
  ).allMatches(text)) {
    final bodyStart = match.start + match.group(0)!.indexOf('(') + 1;
    for (final number in numbers.allMatches(match.group(1)!)) {
      check(
        num.parse(number.group(0)!),
        bodyStart + number.start,
        'EdgeInsets',
      );
    }
  }

  for (final match in RegExp(
    r'SizedBox\(([^()]*)',
    dotAll: true,
  ).allMatches(text)) {
    final bodyStart = match.start + match.group(0)!.indexOf('(') + 1;
    for (final number in RegExp(
      r'(?:width|height):\s*([0-9]+(?:\.[0-9]+)?)',
    ).allMatches(match.group(1)!)) {
      check(num.parse(number.group(1)!), bodyStart + number.start, 'SizedBox');
    }
  }

  return violations;
}
