/// 首页练习入口的 Widget 测试。
///
/// 这里固定住两件事：首屏只展示四个精选入口，「专项练习」不再作为一条
/// 孤立的折叠行挂在卡片外；完整入口在「全部练习」弹层里分组呈现，且每一行
/// 仍能落到正确的学习模式。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/dashboard/cards/practice_card.dart';
import 'package:lexiloop/features/dashboard/practice_catalog.dart';
import 'package:lexiloop/features/dashboard/widgets/practice_sheet.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  /// 挂上最小路由表；`/study` 把 query 原样显示出来，便于断言模式。
  Widget wrap({double textScale = 1}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(child: PracticeCard()),
          ),
        ),
        GoRoute(
          path: '/study',
          builder: (context, state) => Scaffold(
            body: Center(
              child: Text('study:${state.uri.queryParameters['mode']}'),
            ),
          ),
        ),
        GoRoute(
          path: '/games',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('games'))),
        ),
      ],
    );
    addTearDown(router.dispose);
    return MaterialApp.router(
      theme: LexiTheme.light,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    );
  }

  /// 让弹层里的 11 行一次性构建出来，避免测试依赖滚动懒加载。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('首屏只有四个精选入口，其余收进全部练习弹层', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    for (final label in <String>['限时配对', '音标辨音', '听力拼写', '单词拼图']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    // 复古的两条孤儿折叠行必须消失。
    expect(find.text('专项练习'), findsNothing);
    expect(find.text('更多趣味训练'), findsNothing);
    expect(find.text('句子复习'), findsNothing);

    await tester.tap(find.byKey(practiceAllButtonKey));
    await tester.pumpAndSettle();

    expect(find.byKey(practiceSheetKey), findsOneWidget);
    for (final title in <String>['配对与音标', '专项练习', '趣味训练']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    for (final entry in practiceEntries) {
      expect(find.text(entry.label), findsWidgets, reason: entry.label);
    }
    expect(find.byKey(practiceOpenGamesKey), findsOneWidget);
  });

  testWidgets('弹层里的专项入口直达对应学习模式', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(practiceAllButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('句子复习'));
    await tester.pumpAndSettle();

    expect(find.byKey(practiceSheetKey), findsNothing);
    expect(find.text('study:SENTENCE_REVIEW'), findsOneWidget);
  });

  testWidgets('大字号下练习卡不溢出', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(textScale: 2));
    await tester.pumpAndSettle();

    expect(find.byType(PracticeCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
