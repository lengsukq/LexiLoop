/// 词汇地鼠（WHACK_A_MOLE）的纯状态机。
///
/// 对应旧版 `app/(main)/games/whack-a-mole.tsx`：
/// 6 个洞里随机出现候选词，每只地鼠按 [whackAMoleStaggerMs] 依次冒头，
/// 全部冒头后再停留 [whackAMoleStayMs] 就一起缩回；
/// 缩回前没锤中正确的词，该题记为未完成。
///
/// **判定规则与旧版逐条一致**：锤错 → 记一次失误（连击清零），地鼠抖动后
/// 继续停留，可以再锤；锤中正确词 → 该题解决；地鼠全部缩回 → 该题未完成。
///
/// **简化的只是视觉**：旧版用地鼠上下位移的 CSS 关键帧，这里用
/// [WhackAMoleState.isMoleUp] 暴露「第几只已冒头」，由界面决定怎么画。
library;

import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

/// 地鼠洞的分配结果（由注入的随机源决定）。
class WhackAMoleLayout {
  /// 以各字段构造。
  const new({required this.holes, required this.moleCount});

  /// 每个候选词占用的洞号（下标与选项下标一致）。
  final List<int> holes;

  /// 地鼠数量（等于选项数量）。
  final int moleCount;

  /// 全部地鼠缩回的时刻（毫秒，自本题开始计时）。
  int get retreatAtMs =>
      whackAMolePopDelayMs + whackAMoleStaggerMs * moleCount + whackAMoleStayMs;
}

/// 按随机源给 [choiceCount] 只地鼠分配互不相同的洞。
WhackAMoleLayout buildWhackAMoleLayout({
  required int choiceCount,
  required double Function() random,
}) {
  final holes = shuffleWith(<int>[
    for (var index = 0; index < whackAMoleHoleCount; index += 1) index,
  ], random);
  return WhackAMoleLayout(
    holes: holes.take(choiceCount).toList(growable: false),
    moleCount: choiceCount,
  );
}

/// 地鼠游戏的状态。
class WhackAMoleState {
  /// 以各字段构造。
  const new({
    required this.questions,
    required this.layouts,
    required this.core,
    this.itemElapsedMs = 0,
    this.whackedWrong = const <String>{},
    this.solved = false,
    this.failed = false,
  });

  /// 全部题目。
  final List<GameQuestion> questions;

  /// 每题的洞位分配。
  final List<WhackAMoleLayout> layouts;

  /// 计分内核。
  final GameCoreState core;

  /// 当前题已过去的时间。
  final int itemElapsedMs;

  /// 当前题已锤错的选项。
  final Set<String> whackedWrong;

  /// 当前题是否已锤中（等待反馈结束）。
  final bool solved;

  /// 当前题是否已失败（等待反馈结束）。
  final bool failed;

  /// 当前题目；已结束时为 `null`。
  GameQuestion? get current =>
      core.isFinished || core.progress.index >= questions.length
      ? null
      : questions[core.progress.index];

  /// 当前题的洞位分配。
  WhackAMoleLayout? get layout => core.progress.index >= layouts.length
      ? null
      : layouts[core.progress.index];

  /// 第 [index] 只地鼠是否已冒头。
  bool isMoleUp(int index) =>
      itemElapsedMs >= whackAMolePopDelayMs + whackAMoleStaggerMs * index;

  /// 是否已到全部缩回的时刻。
  bool get isRetreatDue {
    final current = layout;
    return current != null && itemElapsedMs >= current.retreatAtMs;
  }

  /// 复制并覆盖部分字段。
  WhackAMoleState copyWith({
    GameCoreState? core,
    int? itemElapsedMs,
    Set<String>? whackedWrong,
    bool? solved,
    bool? failed,
  }) {
    return WhackAMoleState(
      questions: questions,
      layouts: layouts,
      core: core ?? this.core,
      itemElapsedMs: itemElapsedMs ?? this.itemElapsedMs,
      whackedWrong: whackedWrong ?? this.whackedWrong,
      solved: solved ?? this.solved,
      failed: failed ?? this.failed,
    );
  }
}

/// 地鼠游戏的动作。
sealed class WhackAMoleAction {
  /// 供子类继承。
  const new();
}

/// 开始计时。
final class StartWhackAMole extends WhackAMoleAction {
  /// 构造。
  const new();
}

/// 时间前进。
final class TickWhackAMole extends WhackAMoleAction {
  /// 以增量构造。
  const new(this.deltaMs);

  /// 时间增量（毫秒）。
  final int deltaMs;
}

/// 锤击某个候选词。
final class WhackMole extends WhackAMoleAction {
  /// 以选项文本构造。
  const new(this.word);

  /// 被锤中的候选词。
  final String word;
}

/// 地鼠全部缩回（本题未完成）。
final class MoleRetreat extends WhackAMoleAction {
  /// 构造。
  const new();
}

/// 反馈结束，进入下一题。
final class AdvanceWhackAMole extends WhackAMoleAction {
  /// 构造。
  const new();
}

/// 建一局地鼠游戏（洞位由注入的随机源分配）。
WhackAMoleState startWhackAMole({
  required GamePlan plan,
  required List<GameQuestion> questions,
  required double Function() random,
}) {
  final layouts = <WhackAMoleLayout>[
    for (final question in questions)
      buildWhackAMoleLayout(
        choiceCount: question.choices.options.length,
        random: random,
      ),
  ];
  return WhackAMoleState(
    questions: questions,
    layouts: layouts,
    core: GameCoreState(plan: plan),
  );
}

/// 状态机入口：把一个动作应用到状态上，返回新状态。
WhackAMoleState whackAMoleNext(WhackAMoleState state, WhackAMoleAction action) {
  return switch (action) {
    StartWhackAMole() => state.copyWith(core: state.core.start()),
    TickWhackAMole(:final deltaMs) => _tick(state, deltaMs),
    WhackMole(:final word) => _whack(state, word),
    MoleRetreat() => _retreat(state),
    AdvanceWhackAMole() => _advance(state),
  };
}

WhackAMoleState _tick(WhackAMoleState state, int deltaMs) {
  final next = state.copyWith(
    core: state.core.tick(deltaMs: deltaMs),
    itemElapsedMs: state.itemElapsedMs + deltaMs,
  );
  if (next.core.isFinished || next.solved || next.failed) return next;
  return next.isRetreatDue ? _miss(next) : next;
}

WhackAMoleState _whack(WhackAMoleState state, String word) {
  final question = state.current;
  if (question == null || !state.core.isPlaying) return state;
  if (state.solved || state.failed) return state;
  if (word == question.answer) {
    return state.copyWith(
      core: state.core.recordCorrect(
        itemId: question.itemId,
        answerMs: state.itemElapsedMs,
      ),
      solved: true,
    );
  }
  return state.copyWith(
    core: state.core.recordMistake(itemId: question.itemId),
    whackedWrong: <String>{...state.whackedWrong, word},
  );
}

WhackAMoleState _retreat(WhackAMoleState state) {
  if (state.current == null || !state.core.isPlaying) return state;
  if (state.solved || state.failed) return state;
  return _miss(state);
}

WhackAMoleState _advance(WhackAMoleState state) {
  if (state.current == null) return state;
  return WhackAMoleState(
    questions: state.questions,
    layouts: state.layouts,
    core: state.core.advance(),
  );
}

WhackAMoleState _miss(WhackAMoleState state) {
  final question = state.current;
  if (question == null) return state;
  return state.copyWith(
    core: state.core.recordMissed(
      itemId: question.itemId,
      answerMs: state.itemElapsedMs,
    ),
    failed: true,
  );
}
