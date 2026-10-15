/// 今日计划卡片的 Widget 测试。
///
/// 卡片同时承担两件事：把今日队列的三个数字**变成入口**，以及把今日
/// 完成度**显示成进度**。两者都容易「看起来对、其实没接上」——数字对了
/// 但点了没反应，或进度条永远 0%。因此这里断言落点（跳到哪个模式）与
/// 文案（百分比、徽章）而不是截图。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/dashboard/cards/today_plan_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  /// 落在 `/study` 上的实际模式，供断言落点。
  String? landedMode;

  setUp(() => landedMode = null);

  /// 固定的一份计划：三个队列各有可用数，便于断言展示值。
  const plan = DailyStudyPlan(
    dueReviewCount: 8,
    plannedDueReviewCount: 3,
    wrongWordCount: 5,
    plannedWrongWordCount: 2,
    newWordCount: 12,
    plannedNewWordCount: 4,
    sentenceReviewCount: 6,
    plannedSentenceReviewCount: 1,
    plannedTotal: 10,
    activeSessionTasks: 0,
    estimatedMinutes: 7,
  );

  /// 造一份概览；[completed] 与 [goalTotal] 是进度条关心的两个数。
  DashboardOverview overviewOf({required int completed, int goalTotal = 10}) =>
      DashboardOverview(
        totalWords: 30,
        byMastery: const <MasteryLevel, int>{MasteryLevel.newWord: 30},
        dueToday: 8,
        wrongWords: 5,
        reviewedToday: completed,
        streakDays: 3,
        newWordsAvailable: 12,
        completedToday: completed,
        todayGoalTotal: goalTotal,
        todayAccuracy: 0,
        failedWords: 0,
      );

  /// 挂上固定数据与最小路由表后渲染卡片。
  Future<void> showCard(
    WidgetTester tester, {
    required int completed,
    int goalTotal = 10,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(child: TodayPlanCard()),
          ),
        ),
        GoRoute(
          path: '/study',
          builder: (context, state) {
            landedMode = state.uri.queryParameters['mode'];
            return const Scaffold(body: Center(child: Text('学习页')));
          },
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dailyPlanProvider.overrideWith((ref) async => plan),
          dashboardOverviewProvider.overrideWith(
            (ref) async =>
                overviewOf(completed: completed, goalTotal: goalTotal),
          ),
        ],
        child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 点击某个队列行并返回落点上的模式。
  Future<String?> tapQueue(WidgetTester tester, String valueKey) async {
    await tester.tap(find.byKey(Key(valueKey)));
    await tester.pumpAndSettle();
    return landedMode;
  }

  group('队列行是入口', () {
    testWidgets('到期复习进入 DUE_REVIEW', (tester) async {
      await showCard(tester, completed: 0);
      expect(await tapQueue(tester, 'dashboard-due-review'), 'DUE_REVIEW');
    });

    testWidgets('错词进入 WRONG_WORDS', (tester) async {
      await showCard(tester, completed: 0);
      expect(await tapQueue(tester, 'dashboard-wrong-words'), 'WRONG_WORDS');
    });

    testWidgets('新词进入 NEW_WORDS', (tester) async {
      await showCard(tester, completed: 0);
      expect(await tapQueue(tester, 'dashboard-new-words'), 'NEW_WORDS');
    });
  });

  group('今日完成度', () {
    testWidgets('显示已完成数、目标数与百分比', (tester) async {
      await showCard(tester, completed: 5);
      final label = tester.widget<Text>(find.byKey(goalProgressKey)).data;
      expect(label, '5/10 (50%)');
    });

    testWidgets('达标时显示「今日目标已达成」', (tester) async {
      await showCard(tester, completed: 10);
      expect(find.byKey(goalReachedBadgeKey), findsOneWidget);
      expect(find.text('今日目标已达成'), findsOneWidget);
    });

    testWidgets('未达标时不显示徽章', (tester) async {
      await showCard(tester, completed: 9);
      expect(find.byKey(goalReachedBadgeKey), findsNothing);
    });

    testWidgets('目标为 0 时不显示徽章且百分比为 0', (tester) async {
      await showCard(tester, completed: 0, goalTotal: 0);
      expect(find.byKey(goalReachedBadgeKey), findsNothing);
      final label = tester.widget<Text>(find.byKey(goalProgressKey)).data;
      expect(label, '0/0 (0%)');
    });
  });
}
