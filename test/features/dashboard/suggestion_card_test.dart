/// 今日建议卡片的 Widget 测试。
///
/// 这张卡片此前只渲染「一句标题 + 一排词条芯片」，把服务已经算好的
/// 质量分、昨日四项指标、推荐理由与「开始重点复习」入口全部丢在了
/// 计算里。这里逐项把它们钉住：不是断言「页面上有某个 widget」，
/// 而是断言**同一个数字 / 同一句话**在指标区、徽章与列表里各自落在
/// 正确的位置——它们一旦被重新计算或错位，用户看到的就是两套事实。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/dashboard/cards/suggestion_card.dart';
import 'package:lexiloop/features/dashboard/dashboard_providers.dart';
import 'package:lexiloop/services/suggestion_service.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  /// `/study` 落点上的模式，供断言 CTA 去向。
  String? landedMode;

  setUp(() => landedMode = null);

  /// 一份固定的昨日指标：四项都有非平凡值，避免「都是 0」的断言通过。
  const metrics = DailySuggestionMetrics(
    reviewCount: 12,
    correctCount: 9,
    againCount: 2,
    hardCount: 1,
    skippedCount: 3,
    sessionCount: 2,
    studyMinutes: 14,
    accuracy: 75,
    questionAccuracy: <String, int?>{},
  );

  /// 一条推荐词条：术语、题型、释义、理由四样都非空。
  const item = RecommendedStudyItem(
    wordId: 1,
    term: 'apple',
    definition: '苹果',
    reason: '昨天答错 2 次',
    questionType: QuestionType.zhToEnSpelling,
    score: 12,
  );

  /// 造一份建议；默认给满推荐词条与要点，逐条测试再按需清空。
  DailySuggestion suggestionOf({
    int? quality = 92,
    DailySuggestionMetrics stats = metrics,
    List<RecommendedStudyItem> items = const <RecommendedStudyItem>[item],
    List<String> strengths = const <String>['昨天答对 9 题'],
  }) => DailySuggestion(
    dateKey: '2026-03-01',
    sourceDateKey: '2026-02-28',
    metrics: stats,
    headline: '保持状态，做一次精准巩固',
    summary: '昨天完成 12 次作答。',
    strengths: strengths,
    risks: const <String>['跳过了 3 题'],
    actions: const <String>['先完成 3 道重点复习'],
    recommendedItems: items,
    generator: SuggestionGenerator.ruleBased,
    generatedAt: 0,
    qualityScore: quality,
  );

  /// 挂上固定建议与最小路由表后渲染卡片。
  Future<void> showCard(
    WidgetTester tester,
    DailySuggestion? suggestion,
  ) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(child: SuggestionCard()),
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
    final controller = _FixedSuggestionController()..stub = suggestion;
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dailySuggestionProvider.overrideWith(() => controller),
        ],
        child: MaterialApp.router(theme: LexiTheme.light, routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 取「昨日质量」徽章文字的颜色——它承载语气分档。
  Color toneOf(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(suggestionQualityTextKey)).style!.color!;

  /// 取某个指标格的数值文本。
  String metricOf(WidgetTester tester, String metric) =>
      tester.widget<Text>(find.byKey(Key('suggestion-metric-$metric'))).data!;

  group('昨日质量徽章', () {
    testWidgets('高分显示绿色并带出分数', (tester) async {
      await showCard(tester, suggestionOf(quality: highQualityScore));
      expect(
        tester.widget<Text>(find.byKey(suggestionQualityTextKey)).data,
        '昨日质量 $highQualityScore',
      );
      expect(toneOf(tester), LexiColors.light.success);
    });

    testWidgets('中分显示琥珀色', (tester) async {
      await showCard(tester, suggestionOf(quality: 70));
      expect(toneOf(tester), LexiColors.light.warning);
    });

    testWidgets('低分显示红色', (tester) async {
      await showCard(tester, suggestionOf(quality: 40));
      expect(toneOf(tester), LexiColors.light.danger);
    });

    testWidgets('没有分数时用中性灰而不是红色', (tester) async {
      await showCard(tester, suggestionOf(quality: null));
      expect(
        tester.widget<Text>(find.byKey(suggestionQualityTextKey)).data,
        '昨日质量 无记录',
      );
      expect(toneOf(tester), LexiColors.light.quaternaryLabel);
      expect(toneOf(tester), isNot(LexiColors.light.danger));
    });
  });

  group('昨日四项指标', () {
    testWidgets('作答 / 正确率 / 跳过 / 分钟各显示指标上的值', (tester) async {
      await showCard(tester, suggestionOf());
      expect(metricOf(tester, 'answers'), '12');
      expect(metricOf(tester, 'accuracy'), '75%');
      expect(metricOf(tester, 'skipped'), '3');
      expect(metricOf(tester, 'minutes'), '14');
      expect(find.text('作答'), findsOneWidget);
      expect(find.text('正确率'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('分钟'), findsOneWidget);
    });

    testWidgets('昨天没作答时正确率显示破折号而不是 0%', (tester) async {
      await showCard(tester, suggestionOf(stats: DailySuggestionMetrics.empty));
      expect(metricOf(tester, 'accuracy'), '—');
      expect(find.text('0%'), findsNothing);
    });
  });

  group('开始重点复习入口', () {
    testWidgets('有推荐词条时进入 AI_RECOMMENDED', (tester) async {
      await showCard(tester, suggestionOf());
      expect(find.byKey(focusReviewButtonKey), findsOneWidget);
      expect(find.text('开始重点复习'), findsOneWidget);

      await tester.tap(find.byKey(focusReviewButtonKey));
      await tester.pumpAndSettle();

      expect(landedMode, 'AI_RECOMMENDED');
    });

    testWidgets('没有推荐词条时不渲染入口', (tester) async {
      await showCard(
        tester,
        suggestionOf(items: const <RecommendedStudyItem>[]),
      );
      expect(find.byKey(focusReviewButtonKey), findsNothing);
      expect(find.text('开始重点复习'), findsNothing);
      expect(find.text('今日重点复习'), findsNothing);
    });
  });

  group('推荐词条', () {
    testWidgets('同时显示术语、题型、释义与理由', (tester) async {
      await showCard(tester, suggestionOf());
      expect(find.text('apple'), findsOneWidget);
      expect(find.text('中译英拼写'), findsOneWidget);
      expect(find.text('苹果'), findsOneWidget);
      expect(find.text('昨天答错 2 次'), findsOneWidget);
    });

    testWidgets('理由不再藏在 Tooltip 里', (tester) async {
      await showCard(tester, suggestionOf());
      expect(find.byTooltip('昨天答错 2 次'), findsNothing);
    });

    testWidgets('缺释义时其余三项照常显示', (tester) async {
      await showCard(
        tester,
        suggestionOf(
          items: const <RecommendedStudyItem>[
            RecommendedStudyItem(
              wordId: 2,
              term: 'banana',
              reason: '仍在错词队列中',
              questionType: QuestionType.enToZh,
              score: 5,
            ),
          ],
        ),
      );
      expect(find.text('banana'), findsOneWidget);
      expect(find.text('仍在错词队列中'), findsOneWidget);
      expect(find.text('英译中（自评）'), findsOneWidget);
    });
  });

  group('亮点', () {
    testWidgets('strengths 被渲染出来', (tester) async {
      await showCard(tester, suggestionOf());
      expect(find.text('昨天答对 9 题'), findsOneWidget);
    });

    testWidgets('AI 生成时多条亮点全部显示', (tester) async {
      await showCard(
        tester,
        const DailySuggestion(
          dateKey: '2026-03-01',
          sourceDateKey: '2026-02-28',
          metrics: metrics,
          headline: '保持状态',
          summary: '昨天完成 12 次作答。',
          strengths: <String>['亮点一', '亮点二'],
          risks: <String>[],
          actions: <String>[],
          recommendedItems: <RecommendedStudyItem>[],
          generator: SuggestionGenerator.ai,
          generatedAt: 0,
          qualityScore: 88,
        ),
      );
      expect(find.text('亮点一'), findsOneWidget);
      expect(find.text('亮点二'), findsOneWidget);
      expect(find.text('AI 生成'), findsOneWidget);
    });

    testWidgets('没有亮点时不留空标题', (tester) async {
      await showCard(tester, suggestionOf(strengths: const <String>[]));
      expect(find.text('亮点'), findsNothing);
    });
  });
}

/// 只回放固定数据的建议控制器。
///
/// 建议卡片的界面逻辑与 [SuggestionService] 的生成逻辑无关，用真服务
/// 会把数据库、AI 配置一并牵进来，断言的就不是卡片了。
class _FixedSuggestionController extends DailySuggestionController {
  /// 回放的数据；由 `showCard` 在挂载提供者之前写入。
  DailySuggestion? stub;

  @override
  Future<DailySuggestion?> build() async => stub;
}
