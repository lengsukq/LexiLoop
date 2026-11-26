/// 徽章（`LexiBadge`）的**实际渲染**测试。
///
/// **为什么读渲染结果而不是抄公式**：对比度守卫如果自己重算一遍「底色 =
/// 12% 色调压在卡片底上」，那它测的是守卫的公式，不是组件。组件改成压在
/// 页面底上、守卫还压在卡片底上，两边就会一起漂移而无人察觉。这里直接从
/// 渲染树里取 `BoxDecoration.color` 与 `Text.style.color`，测的就是用户
/// 真正看到的那两个颜色。
///
/// 另一半是「长短各一截」：徽章此前有 16 种长相（内边距 4 种、圆角 2 种、
/// 字号写法不一）。这里从几何上钉住——六种色调必须给出**同一个**盒子。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';
import 'package:lexiloop/ui/widgets/badge.dart';

import '../support/contrast.dart';

/// 一枚徽章在渲染树里的样子。
typedef Rendered = ({
  Color background,
  Color foreground,
  EdgeInsets padding,
  BorderRadius radius,
  double fontSize,
  FontWeight weight,
});

/// 渲染一枚徽章并读回它真正画出来的颜色与几何。
Future<Rendered> renderBadge(
  WidgetTester tester,
  LexiBadgeTone tone, {
  Brightness brightness = Brightness.light,
  LexiBadgeEmphasis emphasis = LexiBadgeEmphasis.tint,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? LexiTheme.dark : LexiTheme.light,
      home: Scaffold(
        body: Center(
          child: LexiBadge(label: '示例徽章', tone: tone, emphasis: emphasis),
        ),
      ),
    ),
  );

  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(LexiBadge),
          matching: find.byType(Container),
        )
        .first,
  );
  final decoration = container.decoration! as BoxDecoration;
  final text = tester.widget<Text>(
    find
        .descendant(of: find.byType(LexiBadge), matching: find.byType(Text))
        .first,
  );

  return (
    background: decoration.color!,
    foreground: text.style!.color!,
    padding: container.padding! as EdgeInsets,
    radius: decoration.borderRadius! as BorderRadius,
    fontSize: text.style!.fontSize!,
    weight: text.style!.fontWeight!,
  );
}

void main() {
  group('对比度', () {
    for (final (String mode, Brightness brightness) in <(String, Brightness)>[
      ('浅色', Brightness.light),
      ('深色', Brightness.dark),
    ]) {
      for (final tone in LexiBadgeTone.values) {
        testWidgets('$mode · ${tone.name} 的文字压在自家淡底上 ≥4.5:1', (tester) async {
          final badge = await renderBadge(tester, tone, brightness: brightness);
          final ratio = contrastRatio(badge.foreground, badge.background);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '$mode模式 ${tone.name} 徽章只有 ${ratio.toStringAsFixed(2)}:1。\n'
                '深色下 `*Text` 与填充色同值（如 accent 就是 #0A84FF），压在\n'
                '卡片底 #1C1C1E 上本就只有 4.6:1，再叠一层 12% 同色淡底会掉到\n'
                '4.09:1。所以徽章底色要合成到**页面底**（深色下是纯黑），让\n'
                '底色比卡片更深，而不是更浅。',
          );
        });
      }
    }
  });

  group('几何统一', () {
    testWidgets('六种色调给出同一个盒子', (tester) async {
      final rendered = <LexiBadgeTone, Rendered>{};
      for (final tone in LexiBadgeTone.values) {
        rendered[tone] = await renderBadge(tester, tone);
      }

      final first = rendered[LexiBadgeTone.neutral]!;
      for (final entry in rendered.entries) {
        final badge = entry.value;
        expect(
          badge.padding,
          first.padding,
          reason: '${entry.key.name} 的内边距与其它色调不同',
        );
        expect(
          badge.radius,
          first.radius,
          reason: '${entry.key.name} 的圆角与其它色调不同',
        );
        expect(
          badge.fontSize,
          first.fontSize,
          reason: '${entry.key.name} 的字号与其它色调不同',
        );
        expect(
          badge.weight,
          first.weight,
          reason: '${entry.key.name} 的字重与其它色调不同',
        );
      }

      expect(
        first.padding,
        const EdgeInsets.symmetric(
          horizontal: LexiSpace.s8,
          vertical: LexiSpace.s4,
        ),
      );
      expect(first.radius, BorderRadius.circular(LexiRadius.sm));
    });

    testWidgets('outline 只多一条描边，不改几何', (tester) async {
      final tint = await renderBadge(tester, LexiBadgeTone.accent);
      final outline = await renderBadge(
        tester,
        LexiBadgeTone.accent,
        emphasis: LexiBadgeEmphasis.outline,
      );

      expect(outline.padding, tint.padding);
      expect(outline.radius, tint.radius);
      expect(outline.background, tint.background);

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(LexiBadge),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.border, isNotNull);
    });

    testWidgets('文字压在自家淡底上的对比度与 LexiColors 声明一致', (tester) async {
      // 兜底：徽章的文字色必须取自 `*Text` 一组，而不是饱和填充色。
      final badge = await renderBadge(tester, LexiBadgeTone.success);
      expect(badge.foreground, LexiColors.light.successText);
      expect(
        badge.foreground,
        isNot(LexiColors.light.success),
        reason: '饱和 success 当文字只有 1.99:1，不能用作徽章文字',
      );
    });
  });
}
