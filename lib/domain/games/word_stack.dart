/// 单词堆堆乐（WORD_STACK）的纯状态机。
///
/// 对应旧版 `app/(main)/games/word-stack.tsx`：
/// 给出中文释义，从两行滚动的词块里点中正确的那个，塔就长一层。
///
/// **判定规则与旧版逐条一致**：点错 → 记一次失误（连击清零），该词块
/// 掉落并进入 [wordStackBlockCooldownMs] 冷却，冷却期内不可再点；
/// 点对 → 该题解决，塔层 +1。
///
/// **简化的只是视觉**：旧版用 `block-scroll-left/right` 两行无限滚动动画与
/// 塔块的弹跳关键帧；这里把「滚动词块」渲染成静态的两行网格，
/// 塔层用静态列表展示（只保留最近 [wordStackTowerVisibleCount] 层）。
/// 冷却倒计时在旧版是 `setTimeout`，这里改成随时间递减的剩余毫秒，
/// 因此可以用 `TickWordStack` 直接单测。
library;

import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';

/// 单词堆堆乐的状态。
class WordStackState {
  /// 以各字段构造。
  const new({
    required this.questions,
    required this.core,
    this.droppedMs = const <String, int>{},
    this.itemElapsedMs = 0,
    this.popped = false,
  });

  /// 全部题目。
  final List<GameQuestion> questions;

  /// 计分内核。
  final GameCoreState core;

  /// 处于掉落冷却中的词块 → 剩余冷却毫秒。
  final Map<String, int> droppedMs;

  /// 当前题已过去的时间。
  final int itemElapsedMs;

  /// 当前题是否已点中（等待塔层动画结束）。
  final bool popped;

  /// 当前题目；已结束时为 `null`。
  GameQuestion? get current =>
      core.isFinished || core.progress.index >= questions.length
      ? null
      : questions[core.progress.index];

  /// 该词块当前是否处于冷却中。
  bool isDropped(String word) => (droppedMs[word] ?? 0) > 0;

  /// 已堆起的塔层（全部已解决的词条）。
  List<String> get tower => <String>[
    for (final question in questions)
      if (core.records.isSolved(question.itemId)) question.word.term,
  ];

  /// 复制并覆盖部分字段。
  WordStackState copyWith({
    GameCoreState? core,
    Map<String, int>? droppedMs,
    int? itemElapsedMs,
    bool? popped,
  }) {
    return WordStackState(
      questions: questions,
      core: core ?? this.core,
      droppedMs: droppedMs ?? this.droppedMs,
      itemElapsedMs: itemElapsedMs ?? this.itemElapsedMs,
      popped: popped ?? this.popped,
    );
  }
}

/// 单词堆堆乐的动作。
sealed class WordStackAction {
  /// 供子类继承。
  const new();
}

/// 开始计时。
final class StartWordStack extends WordStackAction {
  /// 构造。
  const new();
}

/// 时间前进（同时推进词块冷却）。
final class TickWordStack extends WordStackAction {
  /// 以增量构造。
  const new(this.deltaMs);

  /// 时间增量（毫秒）。
  final int deltaMs;
}

/// 点选一个词块。
final class TapStackBlock extends WordStackAction {
  /// 以词块文本构造。
  const new(this.word);

  /// 被点中的词块。
  final String word;
}

/// 塔层反馈结束，进入下一题。
final class AdvanceWordStack extends WordStackAction {
  /// 构造。
  const new();
}

/// 建一局单词堆堆乐。
WordStackState startWordStack({
  required GamePlan plan,
  required List<GameQuestion> questions,
}) {
  return WordStackState(
    questions: questions,
    core: GameCoreState(plan: plan),
  );
}

/// 状态机入口。
WordStackState wordStackNext(WordStackState state, WordStackAction action) {
  return switch (action) {
    StartWordStack() => state.copyWith(core: state.core.start()),
    TickWordStack(:final deltaMs) => _tick(state, deltaMs),
    TapStackBlock(:final word) => _tap(state, word),
    AdvanceWordStack() => _advance(state),
  };
}

WordStackState _tick(WordStackState state, int deltaMs) {
  return state.copyWith(
    core: state.core.tick(deltaMs: deltaMs),
    itemElapsedMs: state.itemElapsedMs + deltaMs,
    droppedMs: _decay(state.droppedMs, deltaMs),
  );
}

WordStackState _tap(WordStackState state, String word) {
  final question = state.current;
  if (question == null || !state.core.isPlaying) return state;
  if (state.popped || state.isDropped(word)) return state;
  if (word == question.answer) {
    return state.copyWith(
      core: state.core.recordCorrect(
        itemId: question.itemId,
        answerMs: state.itemElapsedMs,
      ),
      popped: true,
    );
  }
  return state.copyWith(
    core: state.core.recordMistake(itemId: question.itemId),
    droppedMs: <String, int>{
      ...state.droppedMs,
      word: wordStackBlockCooldownMs,
    },
  );
}

WordStackState _advance(WordStackState state) {
  if (state.current == null) return state;
  return WordStackState(
    questions: state.questions,
    core: state.core.advance(),
    droppedMs: state.droppedMs,
  );
}

/// 冷却时间随时间递减，归零的条目直接移除（避免 Map 无限增长）。
Map<String, int> _decay(Map<String, int> droppedMs, int deltaMs) {
  if (droppedMs.isEmpty) return droppedMs;
  final next = <String, int>{};
  for (final entry in droppedMs.entries) {
    final left = entry.value - deltaMs;
    if (left > 0) next[entry.key] = left;
  }
  return next;
}
