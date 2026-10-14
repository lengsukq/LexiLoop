/// 应用外壳的冒烟测试。
///
/// 验证 P0 的核心验收点：应用能构建、双端布局按断点切换。
/// 比截图更可靠——不依赖屏幕录制权限，且能在 CI 中复现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/app.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/features/dashboard/dashboard_page.dart';
import 'package:lexiloop/ui/adaptive_shell.dart';

void main() {
  /// 把测试画布设为指定逻辑尺寸。
  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('应用可构建并渲染首页', (tester) async {
    await setSize(tester, const Size(1280, 900));
    await tester.pumpWidget(const LexiLoopApp());
    await tester.pumpAndSettle();

    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.text('今日'), findsWidgets);
    expect(find.textContaining('LexiLoop'), findsWidgets);
  });

  testWidgets('宽屏使用侧边栏布局', (tester) async {
    await setSize(tester, const Size(1280, 900));
    await tester.pumpWidget(const LexiLoopApp());
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveShell), findsOneWidget);
    // 侧边栏渲染全部 8 个目的地；底部 Tab 只渲染 4 个主项 + 「更多」。
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('统计'), findsOneWidget);
    expect(find.text('更多'), findsNothing);
  });

  testWidgets('窄屏使用底部 Tab 布局', (tester) async {
    await setSize(tester, const Size(390, 844));
    await tester.pumpWidget(const LexiLoopApp());
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveShell), findsOneWidget);
    // 窄屏把非主项收进「更多」。
    expect(find.text('更多'), findsOneWidget);
    expect(find.text('设置'), findsNothing);
    expect(find.text('复习'), findsOneWidget);
  });

  testWidgets('断点两侧的布局确实不同', (tester) async {
    await setSize(tester, const Size(sidebarBreakpoint - 1, 900));
    await tester.pumpWidget(const LexiLoopApp());
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsOneWidget, reason: '断点以下应为底部 Tab');

    await setSize(tester, const Size(sidebarBreakpoint + 1, 900));
    await tester.pumpWidget(const LexiLoopApp());
    await tester.pumpAndSettle();
    expect(find.text('更多'), findsNothing, reason: '断点以上应为侧边栏');
  });

  testWidgets('无 RenderFlex 溢出', (tester) async {
    // 旧版 E2E 用 scrollWidth 断言横向溢出；Flutter 侧对应检查渲染异常。
    await setSize(tester, const Size(390, 844));
    await tester.pumpWidget(const LexiLoopApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
