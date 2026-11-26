/// 「最近学习明细」卡片的 Widget 测试。
///
/// 钉住四件容易做错的事：**倒序**（最新在前）、**只取 30 天**（与趋势档位无关）、
/// **无作答时正确率显示 `—` 而不是 0%**、**宽窄两种形态的列都在**。
///
/// 对应旧版 `app/(main)/statistics/page.tsx:51`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/data/db/daos/statistics_dao.dart';
import 'package:lexiloop/features/statistics/statistics_providers.dart';
import 'package:lexiloop/features/statistics/widgets/recent_daily_detail_card.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

import '../../support/app_harness.dart';

/// 取某个文本的实际颜色。
Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  /// 造一条逐日统计；未指定的字段一律为 0。
  DailyReviewStat statOf({
    required String dateKey,
    int reviewed = 0,
    int correct = 0,
    int again = 0,
    int skipped = 0,
    int sessions = 0,
    int durationMs = 0,
  }) => DailyReviewStat(
    dateKey: dateKey,
    reviewed: reviewed,
    correct: correct,
    again: again,
    skipped: skipped,
    sessions: sessions,
    durationMs: durationMs,
    newWords: 0,
  );

  /// 第 [index] 天的日期键（从 2026-01-01 起）。
  String keyAt(int index) =>
      dateKey(DateTime(2026, 1, 1 + index).millisecondsSinceEpoch);

  /// 渲染明细卡片；[viewportWidth] 用来切换宽窄两种形态。
  Future<void> showDetail(
    WidgetTester tester,
    List<DailyReviewStat> stats, {
    double viewportWidth = 800,
  }) async {
    tester.view.physicalSize = Size(viewportWidth, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dailyTrendProvider.overrideWith((ref) async => stats),
        ],
        child: wrapWithAppTheme(
          const Scaffold(
            body: SingleChildScrollView(child: RecentDailyDetailCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('口径', () {
    test('无作答时正确率显示 —', () {
      expect(accuracyText(statOf(dateKey: '2026-01-01')), '—');
    });

    test('有作答时正确率四舍五入成百分数', () {
      final stat = statOf(dateKey: '2026-01-01', reviewed: 3, correct: 1);
      expect(accuracyText(stat), '33%');
    });

    test('全错时如实显示 0%，不能与「没作答」混淆', () {
      final stat = statOf(dateKey: '2026-01-01', reviewed: 2);
      expect(accuracyText(stat), '0%');
    });

    test('有效时长四舍五入到分钟', () {
      expect(
        minutesOf(statOf(dateKey: '2026-01-01', durationMs: 90 * 1000)),
        2,
      );
      expect(
        minutesOf(statOf(dateKey: '2026-01-01', durationMs: 29 * 1000)),
        0,
      );
      expect(
        minutesOf(statOf(dateKey: '2026-01-01', durationMs: 25 * 60 * 1000)),
        25,
      );
    });
  });

  group('空态', () {
    testWidgets('没有任何一天时给出空态', (tester) async {
      await showDetail(tester, <DailyReviewStat>[]);
      expect(find.text('这段时间还没有学习记录'), findsOneWidget);
    });

    testWidgets('窗口内全是零值时也给出空态', (tester) async {
      await showDetail(tester, <DailyReviewStat>[
        statOf(dateKey: keyAt(0)),
        statOf(dateKey: keyAt(1)),
      ]);
      expect(find.text('这段时间还没有学习记录'), findsOneWidget);
      expect(find.text(keyAt(1)), findsNothing);
    });
  });

  group('截断与顺序', () {
    /// 40 天数据，最新的在最后（与 DAO 的升序输出一致）。
    List<DailyReviewStat> fortyDays() => <DailyReviewStat>[
      for (var index = 0; index < 40; index += 1)
        statOf(dateKey: keyAt(index), reviewed: 1, correct: 1),
    ];

    testWidgets('只取最新 30 天', (tester) async {
      await showDetail(tester, fortyDays());

      // 最新 30 天 = 下标 10..39。
      expect(find.text(keyAt(39)), findsOneWidget);
      expect(find.text(keyAt(10)), findsOneWidget);
      expect(find.text(keyAt(9)), findsNothing, reason: '第 31 新的不该出现');
      expect(find.text(keyAt(0)), findsNothing);
    });

    testWidgets('最新的一天排在最上面', (tester) async {
      await showDetail(tester, fortyDays());

      final newest = tester.getTopLeft(find.text(keyAt(39))).dy;
      final second = tester.getTopLeft(find.text(keyAt(38))).dy;
      expect(newest, lessThan(second));
    });

    testWidgets('30 天这个上限与趋势档位无关', (tester) async {
      // 只给 40 天数据、档位保持默认：上限仍是 statisticsDailyDetailLimit。
      expect(statisticsDailyDetailLimit, 30);
      await showDetail(tester, fortyDays());
      expect(find.text(keyAt(10)), findsOneWidget);
    });
  });

  group('窄屏形态', () {
    testWidgets('渲染卡片式的一天一张', (tester) async {
      await showDetail(tester, <DailyReviewStat>[
        statOf(
          dateKey: '2026-01-02',
          reviewed: 4,
          correct: 3,
          again: 1,
          skipped: 2,
          sessions: 1,
          durationMs: 90 * 1000,
        ),
      ], viewportWidth: 400);

      expect(find.text('2026-01-02'), findsOneWidget);
      expect(find.text('4 次'), findsOneWidget);
      expect(find.text('正确 3'), findsOneWidget);
      expect(find.text('正确率 75%'), findsOneWidget);
      expect(find.text('有效 2 分钟'), findsOneWidget);
      expect(find.text('忘记 1'), findsOneWidget);
      expect(find.text('跳过 2'), findsOneWidget);
      expect(find.text('会话 1'), findsOneWidget);
      expect(find.text('稍后再学'), findsNothing, reason: '窄屏没有表头');
    });

    testWidgets('窄屏也把无作答的正确率显示成 —', (tester) async {
      await showDetail(tester, <DailyReviewStat>[
        // reviewed 默认就是 0：这一天只有会话、没有作答。
        statOf(dateKey: '2026-01-02', sessions: 1),
      ], viewportWidth: 400);

      expect(find.text('正确率 —'), findsOneWidget);
    });
  });

  group('宽屏形态', () {
    testWidgets('渲染表格的 8 个列标题', (tester) async {
      await showDetail(tester, <DailyReviewStat>[
        statOf(dateKey: '2026-01-02', reviewed: 4),
      ], viewportWidth: 900);

      for (final title in detailColumnTitles) {
        expect(find.text(title), findsOneWidget, reason: '缺少列「$title」');
      }
    });

    testWidgets('表格单元格按列着色且数字等宽', (tester) async {
      await showDetail(tester, <DailyReviewStat>[
        statOf(
          dateKey: '2026-01-02',
          reviewed: 4,
          correct: 3,
          again: 7,
          skipped: 8,
          sessions: 9,
          durationMs: 60 * 1000,
        ),
      ], viewportWidth: 900);

      final colors = tester.element(find.text('2026-01-02')).lexiColors;
      expect(_textColor(tester, '3'), colors.success, reason: '正确列用成功色');
      expect(_textColor(tester, '7'), colors.danger, reason: '忘记列用危险色');
      expect(_textColor(tester, '8'), colors.warning, reason: '稍后再学列用警告色');
      expect(find.text('1 分钟'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('2026-01-02')).style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('表格也把无作答的正确率显示成 —', (tester) async {
      await showDetail(tester, <DailyReviewStat>[
        // reviewed 默认就是 0：这一天只有会话、没有作答。
        statOf(dateKey: '2026-01-02', sessions: 1),
      ], viewportWidth: 900);

      expect(find.text('—'), findsOneWidget);
    });
  });
}
