/// 空库引导的 Widget 测试。
///
/// 旧版 `page.tsx:72-87` 在 `totalWords === 0` 时整页换成导入引导。
/// 这里钉住的不是「有没有一个空态 widget」，而是**判据**：只有真的
/// 一条词条都没有才切走——概览还在加载、或词库非空时若也切走，用户
/// 每次冷启动都会先看到一句对自己不成立的「你还没有词条」。
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/today_plan_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_page.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;
  late int now;

  /// 页面最终落到的路径，供断言导入入口的去向。
  String? landedPath;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
    landedPath = null;
  });

  tearDown(() async {
    await db.close();
  });

  /// 挂上最小路由表（含 `/import` 落点）并渲染首页。
  Widget wrap() {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
        GoRoute(
          path: '/study',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('学习页'))),
        ),
        GoRoute(
          path: '/import',
          builder: (context, state) {
            landedPath = state.uri.path;
            return const Scaffold(body: Center(child: Text('导入页')));
          },
        ),
      ],
    );
    return ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        dashboardNowProvider.overrideWithValue(now),
      ],
      child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
    );
  }

  /// 插入一条可学词条（含非空释义），使词库不再是空的。
  Future<void> insertWord(String term) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: const Value<InitializationStatus>(
              InitializationStatus.ready,
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wordContents)
        .insert(
          WordContentsCompanion.insert(
            wordId: Value<int>(id),
            definitionsJson: const Value<String>(
              '[{"language":"zh","text":"释义"}]',
            ),
            updatedAt: now,
          ),
        );
  }

  testWidgets('一个词条都没有时显示导入引导', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(emptyStateTitleKey), findsOneWidget);
    expect(find.text('从 EasyDict 收藏开始'), findsOneWidget);
    expect(find.byKey(emptyStateImportButtonKey), findsOneWidget);
    expect(find.text('导入 CSV'), findsOneWidget);
  });

  testWidgets('空库时不再渲染今日计划的卡片', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(startStudyButtonKey), findsNothing);
  });

  testWidgets('词库非空时回到正常卡片', (tester) async {
    await insertWord('apple');
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.byKey(emptyStateTitleKey), findsNothing);
    expect(find.text('从 EasyDict 收藏开始'), findsNothing);
    expect(find.byKey(startStudyButtonKey), findsOneWidget);
  });

  testWidgets('导入入口跳到 CSV 导入页', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(emptyStateImportButtonKey));
    await tester.pumpAndSettle();

    expect(landedPath, csvImportPath);
    expect(find.text('导入页'), findsOneWidget);
  });

  testWidgets('空库引导不溢出', (tester) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
