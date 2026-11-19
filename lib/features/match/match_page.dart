/// 配对页面（`/match`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lexiloop/features/games/widgets/game_result_panel.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/match/match_board_view.dart';
import 'package:lexiloop/features/match/match_providers.dart';
import 'package:lexiloop/features/match/match_setup_view.dart';
import 'package:lexiloop/ui/navigation/route_paths.dart';
import 'package:lexiloop/ui/widgets/settling_indicator.dart';

/// 配对页面。
class MatchPage extends ConsumerWidget {
  /// 创建配对页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchControllerProvider);
    final controller = ref.read(matchControllerProvider.notifier);

    return GameScaffold(
      onBack: () {
        if (state is MatchSaving) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('正在保存成绩，保存完成后再返回')));
        } else if (state is MatchSetup) {
          context.go(gamesPath);
        } else {
          controller.exit();
        }
      },
      child: switch (state) {
        MatchSetup() => MatchSetupView(
          state: state,
          onSelect: controller.selectPreset,
          onStart: controller.start,
        ),
        MatchPlaying() => MatchBoardView(
          playing: state,
          onAction: controller.dispatch,
          onExit: controller.exit,
        ),
        MatchSaving() => const SettlingIndicator(),
        MatchFinished() => GameResultPanel(
          labels: const GameResultLabels(
            title: '本轮得分',
            primary: '一次配对',
            missed: '未完成',
            exit: '返回',
          ),
          result: state.result,
          // **必须走 restart() 而不是 start()**：结算态不是准备态，
          // start() 的守卫会让这次点击静默失效（按钮看起来能按却没反应）。
          onReplay: controller.restart,
          onExit: controller.exit,
        ),
        MatchSaveFailed() => GameErrorView(
          message: '结算失败：${state.message}',
          onRetry: controller.retrySave,
          // 本轮的成绩还在内存里，重试之外应当允许回去接着打完，
          // 而不是只剩下「从头再来」或「离开」两个都丢进度的选择。
          secondaryLabel: resumeRoundLabel,
          onSecondary: controller.resumeAfterSaveFailure,
        ),
      },
    );
  }
}
