/// 配对页面（`/match`）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/games/widgets/game_result_panel.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/match/match_board_view.dart';
import 'package:lexiloop/features/match/match_providers.dart';
import 'package:lexiloop/features/match/match_setup_view.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 配对页面。
class MatchPage extends ConsumerWidget {
  /// 创建配对页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(matchControllerProvider);
    final controller = ref.read(matchControllerProvider.notifier);

    return GameScaffold(
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
        MatchSaving() => const _SavingView(),
        MatchFinished() => GameResultPanel(
          labels: const GameResultLabels(
            title: '本轮得分',
            primary: '一次配对',
            missed: '未完成',
            exit: '返回',
          ),
          result: state.result,
          onReplay: controller.start,
          onExit: controller.exit,
        ),
        MatchSaveFailed() => GameErrorView(
          message: '结算失败：${state.message}',
          onRetry: controller.retrySave,
        ),
      },
    );
  }
}

class _SavingView extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            '正在结算…',
            style: TextStyle(
              color: context.lexiColors.secondaryLabel,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}
