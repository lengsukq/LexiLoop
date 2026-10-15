/// 小游戏进行中的页面。
///
/// 结构：HUD（倒计时/得分/连击/失误）→ 题干与游戏区 → 退出。
/// 游戏区按运行态类型分派到四个视图之一，每个视图都是纯渲染 +
/// 动作派发，规则不在这里。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_runtime.dart';
import 'package:lexiloop/features/games/games_providers.dart';
import 'package:lexiloop/features/games/widgets/choice_pick_view.dart';
import 'package:lexiloop/features/games/widgets/game_shell.dart';
import 'package:lexiloop/features/games/widgets/whack_a_mole_view.dart';
import 'package:lexiloop/features/games/widgets/word_builder_view.dart';
import 'package:lexiloop/features/games/widgets/word_stack_view.dart';
import 'package:lexiloop/features/games/widgets/word_tetris_view.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
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
      ChoicePickRuntime(:final state) => ChoicePickView(
        state: state,
        onAction: onAction,
      ),
      WhackAMoleRuntime(:final state) => WhackAMoleView(
        state: state,
        onAction: onAction,
      ),
      WordBuilderRuntime(:final state) => WordBuilderView(
        state: state,
        onAction: onAction,
      ),
      WordStackRuntime(:final state) => WordStackView(
        state: state,
        onAction: onAction,
      ),
      WordTetrisRuntime(:final state) => WordTetrisView(
        state: state,
        onAction: onAction,
      ),
    };
  }
}

class _PriorityBadge extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: LexiSpace.s10),
      child: Container(
        decoration: BoxDecoration(
          color: colors.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(LexiRadius.sm),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: LexiSpace.s10,
          vertical: LexiSpace.s4,
        ),
        child: Text(
          '重点复习词',
          style: LexiType.caption.copyWith(
            color: colors.dangerDeep,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
