/// 应用外壳的冒烟测试。
///
/// 验证 P0 的核心验收点：应用能构建、双端布局按断点切换。
/// 比截图更可靠——不依赖屏幕录制权限，且能在 CI 中复现。
///
/// **必须包 `ProviderScope`**：首页等页面依赖数据库与设置，
/// 少了它只会报 `No ProviderScope found`，而那条报错很难指向根因。
/// 数据库用内存实现，测试之间互不污染。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/dashboard/dashboard_page.dart';
import 'package:lexiloop/ui/adaptive_shell.dart';
import 'package:lexiloop/ui/navigation/destinations.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase(NativeDatabase.memory()));
  tearDown(() => database.close());

  /// 把应用包在注入了内存数据库的 [ProviderScope] 里。
  Widget app() => ProviderScope(
    overrides: [databaseProvider.overrideWithValue(database)],
    child: const LexiLoopApp(),
  );

  /// 把测试画布设为指定逻辑尺寸。
  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('应用可构建并渲染首页', (tester) async {
    await setSize(tester, const Size(1280, 900));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.text('今日'), findsWidgets);
    expect(find.textContaining('LexiLoop'), findsWidgets);
  });

  testWidgets('宽屏使用侧边栏布局', (tester) async {
    await setSize(tester, const Size(1280, 900));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveShell), findsOneWidget);
    // 侧边栏渲染全部 8 个目的地；底部 Tab 只渲染 4 个主项 + 「更多」。
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('窄屏使用 4-Tab 底部导航布局', (tester) async {
    await setSize(tester, const Size(390, 844));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveShell), findsOneWidget);
    expect(find.byKey(appBottomBarKey), findsOneWidget);
    expect(find.byKey(appSidebarKey), findsNothing);
    expect(find.text('更多'), findsNothing);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
  });

  testWidgets('断点两侧的布局确实不同', (tester) async {
    await setSize(tester, const Size(sidebarBreakpoint - 1, 900));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(appBottomBarKey), findsOneWidget, reason: '断点以下应为底部 Tab');
    expect(find.byKey(appSidebarKey), findsNothing);

    await setSize(tester, const Size(sidebarBreakpoint + 1, 900));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(appSidebarKey), findsOneWidget, reason: '断点以上应为侧边栏');
    expect(find.byKey(appBottomBarKey), findsNothing);
  });

  testWidgets('无 RenderFlex 溢出', (tester) async {
    // 旧版 E2E 用 scrollWidth 断言横向溢出；Flutter 侧对应检查渲染异常。
    await setSize(tester, const Size(390, 844));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
