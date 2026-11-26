/// 内容层表面（`Surface`）的**结构**测试。
///
/// **为什么单独写它**：把液态玻璃从内容层换成 `Surface` 时，`Surface` 一开始
/// 是 `DecoratedBox`——底色、描边、投影都对，渲染也正常，但 `ListTile` 与
/// `InkWell` 会把背景与涟漪画在「最近的 `Material` 祖先」上，于是涟漪被卡片
/// 底色整个盖住，`ListTile` 还会在 debug 下抛断言。这个缺陷在纯布局测试里
/// 看不出来，只有真的把 `ListTile` 放进去才会炸。
///
/// 这里从结构上钉住：`Surface` 自己必须是承载涟漪的那个 `Material`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

import '../support/app_harness.dart';

/// 取 [Surface] 内部那个承载涟漪的 [Material]。
Material surfaceMaterial(WidgetTester tester) => tester.widget<Material>(
  find.descendant(of: find.byType(Surface), matching: find.byType(Material)),
);

/// 取 [Surface] 的圆角边框（内嵌块没有边框，返回 null）。
RoundedRectangleBorder? surfaceShape(WidgetTester tester) =>
    surfaceMaterial(tester).shape as RoundedRectangleBorder?;

void main() {
  group('承载涟漪', () {
    testWidgets('Surface 里放 ListTile 不报错', (tester) async {
      await tester.pumpWidget(
        wrapWithAppTheme(
          const Scaffold(
            body: Surface(
              child: ListTile(title: Text('一条列表项'), onTap: _noop),
            ),
          ),
        ),
      );

      // 老实现（DecoratedBox）在这里会抛
      // 「ListTile background color or ink splashes may be invisible.」
      expect(tester.takeException(), isNull);
    });

    testWidgets('最近的 Material 祖先就是 Surface 自己', (tester) async {
      await tester.pumpWidget(
        wrapWithAppTheme(
          const Scaffold(
            body: Surface(child: ListTile(title: Text('一条列表项'))),
          ),
        ),
      );

      // 沿 ListTile 往上找 Material，第一个必须落在 Surface 内部；
      // 若 Surface 不是 Material，这个 finder 会一路找到 Scaffold 的那一层。
      final nearest = find
          .ancestor(of: find.byType(ListTile), matching: find.byType(Material))
          .first;
      expect(
        find.descendant(of: find.byType(Surface), matching: nearest),
        findsOneWidget,
      );
    });

    testWidgets('Surface 给后代提供 Material 祖先', (tester) async {
      await tester.pumpWidget(
        wrapWithAppTheme(const Scaffold(body: Surface(child: TextField()))),
      );

      // TextField 依赖 Material 祖先；没有的话 debug 下会整屏红字。
      expect(tester.takeException(), isNull);
    });
  });

  group('三种形态', () {
    testWidgets('阅读面：card 底色 + 发丝描边 + 静置影（不抬升）', (tester) async {
      await tester.pumpWidget(
        wrapWithAppTheme(const Scaffold(body: Surface(child: Text('卡片')))),
      );

      final material = surfaceMaterial(tester);
      expect(material.color, LexiColors.light.card);
      expect(surfaceShape(tester)!.side.color, LexiColors.light.borderSubtle);
      expect(surfaceShape(tester)!.side.width, 1);
      expect(material.elevation, 0);
    });

    testWidgets('内嵌块：fill 底色 + 无描边 + 不抬升', (tester) async {
      await tester.pumpWidget(
        wrapWithAppTheme(
          const Scaffold(
            body: Surface(variant: SurfaceVariant.inset, child: Text('内嵌')),
          ),
        ),
      );

      final material = surfaceMaterial(tester);
      expect(material.color, LexiColors.light.fill);
      expect(surfaceShape(tester)!.side, BorderSide.none);
      expect(material.elevation, 0);
    });

    testWidgets('纯分组：不额外画底与描边', (tester) async {
      await tester.pumpWidget(
        wrapWithAppTheme(
          const Scaffold(
            body: Surface(variant: SurfaceVariant.plain, child: Text('分组')),
          ),
        ),
      );

      // plain 不引入自己的 Material，只会看到 Scaffold 那一层。
      expect(
        find.descendant(
          of: find.byType(Surface),
          matching: find.byType(Material),
        ),
        findsNothing,
      );
      expect(find.text('分组'), findsOneWidget);
    });
  });

  group('无障碍', () {
    testWidgets('增强对比度把描边加重', (tester) async {
      await tester.pumpWidget(
        wrapWithAppTheme(
          const MediaQuery(
            data: MediaQueryData(highContrast: true),
            child: Scaffold(body: Surface(child: Text('卡片'))),
          ),
        ),
      );

      expect(surfaceShape(tester)!.side.color, LexiColors.light.borderStrong);
    });
  });
}

void _noop() {}
