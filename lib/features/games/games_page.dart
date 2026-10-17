/// 小游戏页面（`/games`）。
///
/// 沉浸式路由：不渲染导航外壳，因此自己铺环境光背景。
/// 页面只做状态分派——准备 / 进行中 / 结算中 / 结算完成 / 保存失败，
/// 每个分支一个独立组件文件，避免旧版 `games/page.tsx`（543 行）那种
/// 「一个组件里 5 个阶段 + 4 个游戏分支」的写法。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/features/games/games_play_view.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/games_result_view.dart';
import 'package:lexiloop/features/games/games_setup_view.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/ui/widgets/settling_indicator.dart';

/// 小游戏页面。
class GamesPage extends ConsumerStatefulWidget {
  /// 创建小游戏页面。
  ///
  /// [initialMode] 来自路由 query（形如 `/games?mode=WORD_BUILDER`），
  /// 让首页的「趣味训练」磁贴能直接落到具体游戏，而不是先进选择列表。
  /// 值非法时忽略，退回选择列表。
  const new({this.initialMode, super.key});

  /// 初始游戏模式（`GameMode.wire`）。
  final String? initialMode;

  @override
  ConsumerState<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends ConsumerState<GamesPage> {
  @override
  void initState() {
    super.initState();
    final requested = widget.initialMode;
    if (requested == null) return;
    final mode = GameMode.values
        .where((item) => item.wire == requested)
        .firstOrNull;
    if (mode == null) return;
    // 首帧之后再改 provider：initState 处于构建阶段，此时改状态会触发
    // 「构建期间修改 provider」的断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(gamesControllerProvider.notifier).selectMode(mode);
    });
  }

  @override
  Widget build(BuildContext context) {
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
        GamesSaving() => const SettlingIndicator(),
        GamesFinished() => GamesResultView(
          finished: state,
          onReplay: () => controller.start(state.result.mode),
          onExit: controller.exit,
        ),
        GamesSaveFailed() => GameErrorView(
          message: '结算失败：${state.message}',
          onRetry: controller.retrySave,
          secondaryLabel: resumeRoundLabel,
          onSecondary: controller.resumeAfterSaveFailure,
        ),
      },
    );
  }
}
