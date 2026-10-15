/// 统计页的 Widget 测试。
///
/// 钉住三件相对旧版补齐的行为：
/// - 档位是 7 天 / 30 天 / 90 天 / **一年**（旧版 `statistics/page.tsx:40` 的
///   `Segmented` 最后一档），且切换到它时会带着 `days=365` 重新查库；
/// - 页头有「刷新」按钮，点击后本页四个数据源全部重新查库；
/// - 「最近学习明细」卡片确实挂在页面上。
///
/// 用 mocktail 假 DAO 而不是内存库：这一层要验的是**调用了几次、带了什么参数**，
/// 不是 SQL 口径（那由 `test/data/db/daos/statistics_dao_test.dart` 覆盖）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/statistics/statistics_page.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/app_harness.dart';

/// 记录调用参数的假 DAO。
class _MockStatisticsDao extends Mock implements StatisticsDao;

/// 一份最小的概览。
StatisticsOverview _overview() => const StatisticsOverview(
  totalWords: 12,
  byMastery: <MasteryLevel, int>{MasteryLevel.newWord: 12},
  totalReviews: 4,
  totalCorrect: 3,
  totalDurationMs: 0,
  streakDays: 1,
  activeDays: 1,
);

/// 两条逐日统计。
List<DailyReviewStat> _trend() => const <DailyReviewStat>[
  DailyReviewStat(
    dateKey: '2026-01-01',
    reviewed: 2,
    correct: 2,
    again: 0,
    skipped: 1,
    sessions: 1,
    durationMs: 60000,
    newWords: 1,
  ),
  DailyReviewStat(
    dateKey: '2026-01-02',
    reviewed: 1,
    correct: 0,
    again: 1,
    skipped: 0,
    sessions: 0,
    durationMs: 30000,
    newWords: 0,
  ),
];

void main() {
  late _MockStatisticsDao dao;

  setUp(() {
    dao = _MockStatisticsDao();
    when(() => dao.overview(any())).thenAnswer((_) async => _overview());
    when(
      () => dao.dailyTrend(
        now: any(named: 'now'),
        days: any(named: 'days'),
      ),
    ).thenAnswer((_) async => _trend());
    when(() => dao.accuracyByQuestionType())
        .thenAnswer((_) async => <QuestionTypeAccuracy>[]);
    when(() => dao.recentResults(limit: any(named: 'limit')))
        .thenAnswer((_) async => <bool>[]);
  });

  /// 最近一次 `dailyTrend` 调用带的天数。
  ///
  /// 用 `captureAny` 而不是把 `days` 写死成 `defaultTrendDays`：后者与
  /// 形参默认值相同，会被 `avoid_redundant_argument_values` 判为冗余实参。
  int queriedDays() =>
      verify(
            () => dao.dailyTrend(
              now: any(named: 'now'),
              days: captureAny(named: 'days'),
            ),
          ).captured.last
          as int;

  /// 渲染整页。视口放高，让 `ListView` 把最后一张卡片也建出来。
  Future<void> pumpPage(WidgetTester tester, {double width = 900}) async {
    tester.view.physicalSize = Size(width, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[statisticsDaoProvider.overrideWithValue(dao)],
        child: wrapWithAppTheme(const StatisticsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('趋势档位', () {
    test('档位选项里包含一年', () {
      expect(trendDayOptions, contains(trendYearDays));
      expect(trendYearDays, 365);
    });

    test('一年档位的文案是「一年」而不是「365 天」', () {
      expect(trendRangeLabel(365), '一年');
      expect(trendRangeLabel(7), '7 天');
      expect(trendRangeLabel(30), '30 天');
      expect(trendRangeLabel(90), '90 天');
    });

    testWidgets('四个档位都渲染出来，且没有「365 天」', (tester) async {
      await pumpPage(tester);

      expect(find.text('7 天'), findsOneWidget);
      expect(find.text('30 天'), findsOneWidget);
      expect(find.text('90 天'), findsOneWidget);
      expect(find.text('一年'), findsOneWidget);
      expect(find.text('365 天'), findsNothing);
    });

    testWidgets('切到一年会带着 days=365 重新查库', (tester) async {
      await pumpPage(tester);
      expect(queriedDays(), defaultTrendDays);

      await tester.tap(find.byKey(const Key('statistics-range-365')));
      await tester.pumpAndSettle();

      expect(queriedDays(), trendYearDays);
    });
  });

  group('刷新', () {
    testWidgets('页头有「刷新」按钮', (tester) async {
      await pumpPage(tester);

      expect(find.byKey(const Key('statistics-refresh')), findsOneWidget);
      expect(find.text('刷新'), findsOneWidget);
    });

    testWidgets('点击刷新后本页四个数据源全部重新查库', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.byKey(const Key('statistics-refresh')));
      await tester.pumpAndSettle();

      verify(() => dao.overview(any())).called(2);
      // 一次首屏、一次刷新；两回都该是当前档位（默认 30 天）。
      final trend = verify(
        () => dao.dailyTrend(
          now: any(named: 'now'),
          days: captureAny(named: 'days'),
        ),
      );
      expect(trend.callCount, 2);
      expect(trend.captured, <int>[defaultTrendDays, defaultTrendDays]);
      verify(() => dao.accuracyByQuestionType()).called(2);
      verify(() => dao.recentResults(limit: recentResultsLimit)).called(2);
    });
  });

  group('布局', () {
    testWidgets('窄屏不溢出', (tester) async {
      await pumpPage(tester, width: 360);

      expect(tester.takeException(), isNull);
    });
  });

  group('最近学习明细', () {
    testWidgets('卡片挂在页面上并列出最近几天', (tester) async {
      await pumpPage(tester);

      expect(find.text('最近学习明细'), findsOneWidget);
      expect(find.text('2026-01-02'), findsOneWidget);
      expect(find.text('2026-01-01'), findsOneWidget);
      expect(find.text('稍后再学'), findsOneWidget, reason: '宽屏是表格形态');
    });
  });
}
