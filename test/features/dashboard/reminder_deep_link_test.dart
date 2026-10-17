/// 提醒卡的按钮必须落到**对应的筛选视图**。
///
/// 卡片上写着「错词 12」，点「查看错词」却落在未筛选的完整词库上——
/// 12 个错词混在几千个词里，用户得自己去筛选栏再勾一次。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/features/dashboard/cards/reminders_card.dart';
import 'package:lexiloop/features/words/words_providers.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> pumpCard(WidgetTester tester) async {
    final overrides = <Override>[databaseProvider.overrideWithValue(db)];
    container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // 需要真的路由：按钮会 `go` 到单词本，非路由环境会抛
    // 「No GoRouter found in context」，那样测不到筛选是否落地。
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: RemindersCard()),
        ),
        GoRoute(
          path: wordsPath,
          builder: (_, _) => const Scaffold(body: Text('单词本占位')),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('「查看错词」把词库筛选设成只看活跃错词', (tester) async {
    await pumpCard(tester);

    expect(container.read(wordQueryProvider).wrongOnly, isFalse);
    await tester.tap(find.text('查看错词'));
    await tester.pumpAndSettle();

    expect(container.read(wordQueryProvider).wrongOnly, isTrue);
    // 并且真的到了单词本。
    expect(find.text('单词本占位'), findsOneWidget);
  });

  testWidgets('「查看到期」把词库筛选设成只看今日到期', (tester) async {
    await pumpCard(tester);

    expect(container.read(wordQueryProvider).dueOnly, isFalse);
    await tester.tap(find.text('查看到期'));
    await tester.pumpAndSettle();

    expect(container.read(wordQueryProvider).dueOnly, isTrue);
    expect(find.text('单词本占位'), findsOneWidget);
  });
}
