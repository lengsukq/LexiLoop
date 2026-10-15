/// 进行中一局的状态机联合类型。
///
/// 界面只持有 [GameRuntime] 一个引用，通过 [GameRuntime.dispatch] 派发动作，
/// 不需要知道当前是哪个游戏——旧版 `games/page.tsx` 正是在这里堆了
/// 4 个 `if (mode === "...")` 分支加上 12 个 `useState`，才涨到 543 行。
///
/// **动作与游戏不匹配时返回 `null`**，而不是抛错：界面可能因为动画延迟
/// 派发上一个游戏的动作，这类竞态不该让游戏崩掉。
library;

import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/whack_a_mole.dart';
import 'package:lexiloop/domain/games/word_builder.dart';
import 'package:lexiloop/domain/games/word_stack.dart';
import 'package:lexiloop/domain/games/word_tetris.dart';

/// 进行中一局的状态机。
sealed class GameRuntime {
  /// 供子类继承。
  const new();

  /// 计分内核。
  GameCoreState get core;

  /// 当前题目；已结束时为 `null`。
  GameQuestion? get current;

  /// 派发一个动作；动作与游戏不匹配时返回 `null`。
  GameRuntime? dispatch(Object action);

  /// 本题是否已判定、正在等待反馈动画结束（随后自动进入下一题）。
  ///
  /// 单词拼图的「不认识」流程**不**算在这里：它要等用户点「继续」。
  bool get awaitingAdvance;
}

/// 词汇地鼠的运行态。
final class WhackAMoleRuntime extends GameRuntime {
  /// 以状态机状态构造。
  const new(this.state);

  /// 状态机状态。
  final WhackAMoleState state;

  @override
  GameCoreState get core => state.core;

  @override
  GameQuestion? get current => state.current;

  @override
  GameRuntime? dispatch(Object action) => action is WhackAMoleAction
      ? WhackAMoleRuntime(whackAMoleNext(state, action))
      : null;

  @override
  bool get awaitingAdvance => state.solved || state.failed;
}

/// 单词拼图的运行态。
final class WordBuilderRuntime extends GameRuntime {
  /// 以状态机状态构造。
  const new(this.state);

  /// 状态机状态。
  final WordBuilderState state;

  @override
  GameCoreState get core => state.core;

  @override
  GameQuestion? get current => state.current;

  @override
  GameRuntime? dispatch(Object action) => action is WordBuilderAction
      ? WordBuilderRuntime(wordBuilderNext(state, action))
      : null;

  @override
  bool get awaitingAdvance {
    final question = state.current;
    return question != null && state.core.records.isSolved(question.itemId);
  }
}

/// 单词堆堆乐的运行态。
final class WordStackRuntime extends GameRuntime {
  /// 以状态机状态构造。
  const new(this.state);

  /// 状态机状态。
  final WordStackState state;

  @override
  GameCoreState get core => state.core;

  @override
  GameQuestion? get current => state.current;

  @override
  GameRuntime? dispatch(Object action) => action is WordStackAction
      ? WordStackRuntime(wordStackNext(state, action))
      : null;

  @override
  bool get awaitingAdvance => state.popped;
}

/// 词汇俄罗斯方块的运行态。
final class WordTetrisRuntime extends GameRuntime {
  /// 以状态机状态构造。
  const new(this.state);

  /// 状态机状态。
  final WordTetrisState state;

  @override
  GameCoreState get core => state.core;

  @override
  GameQuestion? get current => state.current;

  @override
  GameRuntime? dispatch(Object action) => action is WordTetrisAction
      ? WordTetrisRuntime(wordTetrisNext(state, action))
      : null;

  @override
  bool get awaitingAdvance {
    final question = state.current;
    return question != null && state.core.records.isSolved(question.itemId);
  }
}

/// 该模式对应的「开始」动作。
Object startActionFor(GameMode mode) => switch (mode) {
  GameMode.whackAMole => const StartWhackAMole(),
  GameMode.wordStack => const StartWordStack(),
  GameMode.wordTetris => const StartWordTetris(),
  _ => const StartWordBuilder(),
};

/// 该模式对应的「时间前进」动作。
Object tickActionFor(GameMode mode, int deltaMs) => switch (mode) {
  GameMode.whackAMole => TickWhackAMole(deltaMs),
  GameMode.wordStack => TickWordStack(deltaMs),
  GameMode.wordTetris => TickWordTetris(deltaMs),
  _ => TickWordBuilder(deltaMs),
};

/// 该模式对应的「进入下一题」动作。
Object advanceActionFor(GameMode mode) => switch (mode) {
  GameMode.whackAMole => const AdvanceWhackAMole(),
  GameMode.wordStack => const AdvanceWordStack(),
  GameMode.wordTetris => const AdvanceWordTetris(),
  _ => const AdvanceWordBuilder(),
};

/// 按模式建一局运行态并立即开始计时。
///
/// 随机源由调用方注入，保证「给定随机序列应得到什么题面」可断言。
GameRuntime startGameRuntime({
  required GameMode mode,
  required GamePlan plan,
  required List<GameQuestion> questions,
  required double Function() random,
}) {
  final runtime = _createRuntime(
    mode: mode,
    plan: plan,
    questions: questions,
    random: random,
  );
  return runtime.dispatch(startActionFor(mode)) ?? runtime;
}

GameRuntime _createRuntime({
  required GameMode mode,
  required GamePlan plan,
  required List<GameQuestion> questions,
  required double Function() random,
}) {
  return switch (mode) {
    GameMode.whackAMole => WhackAMoleRuntime(
      startWhackAMole(plan: plan, questions: questions, random: random),
    ),
    GameMode.wordStack => WordStackRuntime(
      startWordStack(plan: plan, questions: questions),
    ),
    GameMode.wordTetris => WordTetrisRuntime(
      startWordTetris(plan: plan, questions: questions, random: random),
    ),
    _ => WordBuilderRuntime(startWordBuilder(plan: plan, questions: questions)),
  };
}
