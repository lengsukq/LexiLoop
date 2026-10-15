/// 小游戏页面（`/games`）。
///
/// 沉浸式路由：不渲染导航外壳，因此自己铺环境光背景。
/// 页面只做状态分派——准备 / 进行中 / 结算中 / 结算完成 / 保存失败，
/// 每个分支一个独立组件文件，避免旧版 `games/page.tsx`（543 行）那种
/// 「一个组件里 5 个阶段 + 4 个游戏分支」的写法。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/features/games/games_play_view.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/games_result_view.dart';
import 'package:lexiloop/features/games/games_setup_view.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 小游戏页面。
class GamesPage extends ConsumerWidget {
  /// 创建小游戏页面。
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamesControllerProvider);
    final controller = ref.read(gamesControllerProvider.notifier);

    return GameScaffold(
      child: switch (state) {
        GamesSetup() => GamesSetupView(
          state: state,
          onSelect: controller.selectMode,
          onStart: controller.start,
        ),
        GamesPlaying() => GamesPlayView(
          playing: state,
          onAction: controller.dispatch,
          onExit: controller.exit,
        ),
        GamesSaving() => const _SavingView(),
        GamesFinished() => GamesResultView(
          finished: state,
          onReplay: () => controller.start(state.result.mode),
          onExit: controller.exit,
        ),
        GamesSaveFailed() => GameErrorView(
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
    final colors = context.lexiColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(
            '正在结算…',
            style: TextStyle(color: colors.secondaryLabel, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
