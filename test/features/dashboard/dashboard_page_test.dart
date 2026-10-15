/// 仪表盘的 Widget 测试。
///
/// 首页最容易犯的错是「显示了一个数字，但那个数字不是真的」——旧版
/// `import/page.tsx` 写死 `value={75}` 的假进度条就是先例。因此这里不满足于
/// 「有数字」，而是用真实的 `StudyService` 与 `WordDetailDao` 算出期望值，
/// 再断言界面上显示的确实是同一组数。
library;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/daos/settings_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/statistics_card.dart';
import 'package:lexiloop/features/dashboard/cards/today_plan_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_page.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/services/settings_service.dart';
import 'package:lexiloop/services/study_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  late AppDatabase db;
  late int now;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;
  });

  tearDown(() async {
    await db.close();
  });

  /// 用内存库与固定时钟替换提供者，并挂上最小路由表。
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
          path: '/words',
          builder: (context, state) =>
              const Scaffold(body: Center(child: Text('单词本页'))),
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

  /// 把测试画布调高，让整页卡片都被真实构建。
  ///
  /// `ListView` 只构建可见项，默认 800x600 的画布下「提醒」卡片不会被
  /// inflate，`find.byKey` 自然找不到它——这是测试视口的问题，不是组件的问题。
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 插入一条可学词条（READY、未暂停、无卡片），并写入一条非空释义。
  ///
  /// 释义不能省：候选池的准入条件要求「存在非空释义」，
  /// 没有内容的词条既不算可用新词，也进不了今日计划。
  Future<int> insertWord({
    required String term,
    InitializationStatus status = InitializationStatus.ready,
    bool isSuspended = false,
  }) async {
    final id = await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            term: term,
            normalizedTerm: term.toLowerCase(),
            sourceLanguage: 'en',
            targetLanguage: 'zh',
            entryType: EntryType.word,
            initializationStatus: Value<InitializationStatus>(status),
            isSuspended: Value<bool>(isSuspended),
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
              '[{"language":"zh","text":"苹果"}]',
            ),
            updatedAt: now,
          ),
        );
    return id;
  }

  /// 取带 Key 的文本内容。
  String textOf(WidgetTester tester, Key key) =>
      tester.widget<Text>(find.byKey(key)).data!;

  testWidgets('今日计划显示服务算出的计划数与可用数', (tester) async {
    useTallViewport(tester);
    await insertWord(term: 'apple');
    await insertWord(term: 'banana');

    final service = StudyService(db, SettingsService(SettingsDao(db)));
    final plan = await service.dailyPlan(now: now);
    expect(plan.newWordCount, 2, reason: '两条无卡片的新词都应可用');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(textOf(tester, plannedTotalKey), '${plan.plannedTotal}');
    expect(
      textOf(tester, const Key('dashboard-new-words')),
      '${plan.plannedNewWordCount}',
    );
    expect(
      textOf(tester, const Key('dashboard-due-review')),
      '${plan.plannedDueReviewCount}',
    );
    expect(find.text('预估 ${plan.estimatedMinutes} 分钟'), findsOneWidget);
  });

  testWidgets('学习统计显示真实总词数与掌握分布', (tester) async {
    useTallViewport(tester);
    await insertWord(term: 'apple');
    await insertWord(term: 'banana');
    await insertWord(term: 'cherry');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(textOf(tester, totalWordsKey), '3');
    expect(find.text('个词条'), findsOneWidget);
    // 三条都是新词，分布行里的计数应为 3。
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('提醒卡片显示到期数与错词数', (tester) async {
    useTallViewport(tester);
    final due = await insertWord(term: 'apple');
    await insertWord(term: 'banana');
    await db
        .into(db.reviewCards)
        .insert(
          ReviewCardsCompanion.insert(
            wordId: Value<int>(due),
            dueAt: now - 1000,
            stability: 1,
            difficulty: 5,
            elapsedDays: 0,
            scheduledDays: 1,
            reps: 1,
            lapses: 0,
            fsrsState: 1,
            createdAt: now,
            updatedAt: now,
          ),
        );
    await db
        .into(db.wrongWordStates)
        .insert(
          WrongWordStatesCompanion.insert(
            wordId: Value<int>(due),
            active: const Value<bool>(true),
            updatedAt: now,
          ),
        );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(textOf(tester, const Key('dashboard-due-count')), '1');
    expect(textOf(tester, const Key('dashboard-wrong-count')), '1');
  });

  testWidgets('「开始学习」按钮存在且可点击并跳转到复习页', (tester) async {
    useTallViewport(tester);
    await insertWord(term: 'apple');

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(find.byKey(startStudyButtonKey));
    expect(button.onPressed, isNotNull);

    await tester.ensureVisible(find.byKey(startStudyButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(startStudyButtonKey));
    await tester.pumpAndSettle();

    expect(find.text('学习页'), findsOneWidget);
  });

  testWidgets('空库时切到导入引导且不溢出', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // 总词数为 0 时首页换成导入引导，六张卡片不再渲染——零词条时它们
    // 只会显示一排 0，对「下一步做什么」没有任何信息量。
    expect(find.text('今日'), findsOneWidget);
    // 断言整句而不是 `textContaining('LexiLoop')`：空态的说明文案里
    // 也出现了「LexiLoop」，模糊匹配会命中两处。
    expect(find.text('LexiLoop 词环 · 纯本地'), findsOneWidget);
    expect(find.byKey(emptyStateTitleKey), findsOneWidget);
    expect(find.byKey(totalWordsKey), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
