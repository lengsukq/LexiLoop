/// 小游戏进行中的页面。
///
/// 结构：HUD（倒计时/得分/连击/失误）→ 题干与拼词交互区 → 退出。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_runtime.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/games/widgets/word_builder_view.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/widgets/badge.dart';
import 'package:lexiloop/ui/widgets/surface.dart';

/// 小游戏进行中页面。
class GamesPlayView extends StatelessWidget {
  /// 以进行中状态与回调构造。
  const new({
    required this.playing,
    required this.onAction,
    required this.onExit,
    super.key,
  });

  /// 进行中状态。
  final GamesPlaying playing;

  /// 动作派发。
  final ValueChanged<Object> onAction;

  /// 退出回调。
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final mode = playing.session.mode;
    return Column(
      children: <Widget>[
        GameHud(title: gameModeTitle(mode), core: playing.core, onExit: onExit),
        const SizedBox(height: LexiSpace.s12),
        Expanded(
          child: Surface(
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(LexiRadius.xl),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(LexiSpace.s16),
              child: Column(
                children: <Widget>[
                  if (playing.current != null &&
                      playing.current!.priority != GamePriority.normal)
                    const _PriorityBadge(),
                  _GameArea(runtime: playing.runtime, onAction: onAction),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GameArea extends StatelessWidget {
  const new({required this.runtime, required this.onAction});

  final GameRuntime runtime;
  final ValueChanged<Object> onAction;

  @override
  Widget build(BuildContext context) {
    return switch (runtime) {
      WordBuilderRuntime(:final state) => WordBuilderView(
        state: state,
        onAction: onAction,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _PriorityBadge extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(bottom: LexiSpace.s10),
    child: LexiBadge(label: '重点复习词', tone: LexiBadgeTone.danger),
  );
}
