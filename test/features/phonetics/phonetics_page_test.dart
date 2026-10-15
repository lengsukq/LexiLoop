/// 音标页的 widget 测试。
///
/// 结算态要显示正确率（规格点名的验收点）。结算面板是纯展示组件，
/// 直接构造一份 [GameResult] 渲染即可，不需要数据库。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/data/db/daos/game_dao.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/scoring.dart';
import 'package:lexiloop/features/phonetics/phonetics_setup_view.dart';
import 'package:lexiloop/services/game_service.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

void main() {
  GameResult buildResult({required int accuracy}) {
    final summary = GameRoundSummary(
      answerScore: 520,
      firstTryCorrect: accuracy == 100 ? 5 : 4,
      recovered: accuracy == 100 ? 0 : 1,
      missed: 0,
      mistakeCount: 2,
      maxCombo: 3,
      elapsedMs: 42000,
      durationMs: 75000,
    );
    return GameResult(
      mode: GameMode.phonetics,
      score: 520,
      summary: summary,
      rank: rankFor(score: 520, mode: GameMode.phonetics),
      leaderboard: GameLeaderboard(
        rank: 2,
        best: 900,
        top: <GameHighScore>[
          GameHighScore(
            mode: GameMode.phonetics,
            score: 900,
            detail: const GameScoreDetail(
              maxCombo: 6,
              accuracy: 100,
              elapsedMs: 30000,
            ),
            playedAt: DateTime(2026, 3, 1, 9).millisecondsSinceEpoch,
          ),
          GameHighScore(
            mode: GameMode.phonetics,
            score: 520,
            detail: const GameScoreDetail(
              maxCombo: 3,
              accuracy: 80,
              elapsedMs: 42000,
            ),
            playedAt: DateTime(2026, 3, 1, 10).millisecondsSinceEpoch,
          ),
        ],
        isNewBest: false,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: LexiTheme.light,
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  group('结算页', () {
    testWidgets('显示得分、评级、正确率与历史最高分', (tester) async {
      await pump(
        tester,
        PhoneticsResultView(
          result: buildResult(accuracy: 80),
          onReplay: () {},
          onExit: () {},
        ),
      );
      expect(find.text('音标训练得分'), findsOneWidget);
      expect(find.text('520'), findsWidgets);
      expect(find.text('一次正确率'), findsOneWidget);
      expect(find.text('80%'), findsOneWidget);
      expect(find.textContaining('评级'), findsOneWidget);
      expect(find.textContaining('历史最高分 900'), findsOneWidget);
      expect(find.text('再来一局'), findsOneWidget);
      expect(find.text('更换口音'), findsOneWidget);
      expect(find.text('一次听对'), findsOneWidget);
      expect(find.text('超时或跳过'), findsOneWidget);
    });

    testWidgets('正确率进度条与文本一致', (tester) async {
      await pump(
        tester,
        PhoneticsResultView(
          result: buildResult(accuracy: 100),
          onReplay: () {},
          onExit: () {},
        ),
      );
      expect(find.text('100%'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 1);
    });

    testWidgets('点击按钮触发回调', (tester) async {
      var replayed = 0;
      var exited = 0;
      await pump(
        tester,
        PhoneticsResultView(
          result: buildResult(accuracy: 80),
          onReplay: () => replayed += 1,
          onExit: () => exited += 1,
        ),
      );
      await tester.tap(find.text('再来一局'));
      await tester.tap(find.text('更换口音'));
      await tester.pump();
      expect(replayed, 1);
      expect(exited, 1);
    });
  });
}
