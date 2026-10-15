/// 听音辨词（LISTENING_PICK）与词义冲刺（MEANING_BLITZ）共用的纯状态机。
///
/// 对应旧版 `app/(main)/games/page.tsx` 的 `chooseAnswer`（第 217 行）与
/// 第 297-310 行两段内联题面：两个模式的规则完全相同——点一个选项，
/// 点对了进下一题；点错了扣分、红框反馈 [gameWrongChoiceFeedbackMs] 毫秒后
/// 可以再点，直到点对为止（没有「失败」路径，只有时间耗尽）。
///
/// **为什么两个模式共用一个状态机**：旧版这两个模式本来就共用同一段
/// `ChoiceGrid` + `chooseAnswer` 代码，区别只在题面（喇叭按钮 / 大字词条）
/// 与选项文本。拆成两份会让「点错红框停多久」「什么时候能再点」出现两处实现。
///
/// **与旧版的差异**：旧版点错后靠 `window.setTimeout(..., 420)` 清掉红框，
/// 这段等待因此无法单测；这里把剩余毫秒存进状态，由 [TickChoicePick] 递减，
/// 「反馈期内不可作答」就能用一条断言钉住。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';

/// 选择题的状态。
class ChoicePickState {
  /// 以各字段构造。
  const new({
    required this.questions,
    required this.core,
    this.itemElapsedMs = 0,
    this.wrongChoice,
    this.wrongChoiceMs = 0,
  });

  /// 全部题目。
  final List<GameQuestion> questions;

  /// 计分内核。
  final GameCoreState core;

  /// 当前题已过去的时间（作答耗时与速度加减分用）。
  final int itemElapsedMs;

  /// 当前题最近一次点错的选项（红框反馈中）；为空表示没有待清掉的反馈。
  final String? wrongChoice;

  /// 红框反馈的剩余毫秒。
  final int wrongChoiceMs;

  /// 当前题目；已结束时为 `null`。
  GameQuestion? get current =>
      core.isFinished || core.progress.index >= questions.length
      ? null
      : questions[core.progress.index];

  /// 当前题是否已点对（等待反馈结束进入下一题）。
  ///
  /// 从作答记录推导而不是另存一个布尔量：否则「已点对」与「记录里有这题」
  /// 两个事实可能不一致，结算时会漏掉一题。
  bool get solved {
    final question = current;
    return question != null && core.records.isSolved(question.itemId);
  }

  /// 反馈期内是否禁止作答（点对后的过场动画或点错后的红框）。
  bool get isLocked => solved || wrongChoiceMs > 0;
}

/// 选择题的动作。
sealed class ChoicePickAction {
  /// 供子类继承。
  const new();
}

/// 开始计时。
final class StartChoicePick extends ChoicePickAction {
  /// 构造。
  const new();
}

/// 时间前进（同时递减红框反馈的剩余毫秒）。
final class TickChoicePick extends ChoicePickAction {
  /// 以增量构造。
  const new(this.deltaMs);

  /// 时间增量（毫秒）。
  final int deltaMs;
}

/// 点选一个选项。
final class PickChoice extends ChoicePickAction {
  /// 以选项文本构造。
  const new(this.choice);

  /// 被点中的选项文本。
  final String choice;
}

/// 反馈结束，进入下一题。
final class AdvanceChoicePick extends ChoicePickAction {
  /// 构造。
  const new();
}

/// 建一局选择题。
ChoicePickState startChoicePick({
  required GamePlan plan,
  required List<GameQuestion> questions,
}) {
  return ChoicePickState(
    questions: questions,
    core: GameCoreState(plan: plan),
  );
}

/// 状态机入口：把一个动作应用到状态上，返回新状态。
ChoicePickState choicePickNext(ChoicePickState state, ChoicePickAction action) {
  return switch (action) {
    StartChoicePick() => _withCore(state, state.core.start()),
    TickChoicePick(:final deltaMs) => _tick(state, deltaMs),
    PickChoice(:final choice) => _pick(state, choice),
    AdvanceChoicePick() => _advance(state),
  };
}

ChoicePickState _tick(ChoicePickState state, int deltaMs) {
  final left = state.wrongChoiceMs - deltaMs;
  final expired = left <= 0;
  return ChoicePickState(
    questions: state.questions,
    core: state.core.tick(deltaMs: deltaMs),
    itemElapsedMs: state.itemElapsedMs + deltaMs,
    wrongChoice: expired ? null : state.wrongChoice,
    wrongChoiceMs: expired ? 0 : left,
  );
}

ChoicePickState _pick(ChoicePickState state, String choice) {
  final question = state.current;
  if (question == null || !state.core.isPlaying || state.isLocked) return state;
  if (choice == question.answer) {
    return _withCore(
      state,
      state.core.recordCorrect(
        itemId: question.itemId,
        answerMs: state.itemElapsedMs,
      ),
    );
  }
  return ChoicePickState(
    questions: state.questions,
    core: state.core.recordMistake(itemId: question.itemId),
    itemElapsedMs: state.itemElapsedMs,
    wrongChoice: choice,
    wrongChoiceMs: gameWrongChoiceFeedbackMs,
  );
}

ChoicePickState _advance(ChoicePickState state) {
  if (state.current == null) return state;
  // 逐题状态（耗时、红框）随换题一起归零，与旧版 `advanceToNext` 一致。
  return ChoicePickState(
    questions: state.questions,
    core: state.core.advance(),
  );
}

/// 只替换计分内核，保留逐题状态。
ChoicePickState _withCore(ChoicePickState state, GameCoreState core) {
  return ChoicePickState(
    questions: state.questions,
    core: core,
    itemElapsedMs: state.itemElapsedMs,
    wrongChoice: state.wrongChoice,
    wrongChoiceMs: state.wrongChoiceMs,
  );
}
