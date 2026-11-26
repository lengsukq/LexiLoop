/// 学习统计卡片里「今日正确率」的 Widget 测试。
///
/// [DashboardOverview.todayAccuracy] 早就被算出来并测过，却一直没有被渲染。
/// 这里钉住两件事：有作答时百分比必须与概览里的同一组数字一致；
/// **没有作答时不能显示成 0%**——那会被读成「今天全错了」，而事实是
/// 今天还没开始，这个读法错误比「少显示一个数」严重得多。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/word_detail_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/statistics_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';

import '../../support/app_harness.dart';

void main() {
  /// 造一份概览；[reviewed] 与 [accuracy] 是这一行关心的两个数。
  DashboardOverview overviewOf({
    required int reviewed,
    required double accuracy,
  }) => DashboardOverview(
    totalWords: 30,
    byMastery: const <MasteryLevel, int>{MasteryLevel.newWord: 30},
    dueToday: 8,
    wrongWords: 5,
    reviewedToday: reviewed,
    streakDays: 3,
    newWordsAvailable: 12,
    completedToday: reviewed,
    todayGoalTotal: reviewed + 10,
    todayAccuracy: accuracy,
    failedWords: 0,
  );

  /// 挂上固定概览后渲染统计卡片。
  Future<void> showCard(WidgetTester tester, DashboardOverview overview) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dashboardOverviewProvider.overrideWith((ref) async => overview),
        ],
        child: wrapWithAppTheme(
          const Scaffold(body: SingleChildScrollView(child: StatisticsCard())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 「今日已答」一行右侧的补充说明文本。
  String noteText(WidgetTester tester) =>
      tester.widgetList<Text>(find.textContaining('题 ·')).single.data!;

  testWidgets('有作答时把正确率换算成百分数显示', (tester) async {
    await showCard(tester, overviewOf(reviewed: 4, accuracy: 0.75));
    expect(noteText(tester), ' 题 · 正确率 75%');
    expect(
      tester
          .widget<Text>(find.byKey(const Key('dashboard-reviewed-today')))
          .data,
      '4',
    );
  });

  testWidgets('正确率向下取整到整数百分比', (tester) async {
    await showCard(tester, overviewOf(reviewed: 3, accuracy: 0.66));
    expect(noteText(tester), ' 题 · 正确率 66%');
  });

  testWidgets('今天还没作答时不显示 0%', (tester) async {
    await showCard(tester, overviewOf(reviewed: 0, accuracy: 0));
    expect(noteText(tester), ' 题 · 今日尚无作答');
    expect(find.textContaining('正确率'), findsNothing);
  });

  testWidgets('全答错时如实显示 0%', (tester) async {
    await showCard(tester, overviewOf(reviewed: 5, accuracy: 0));
    expect(noteText(tester), ' 题 · 正确率 0%');
  });
}
