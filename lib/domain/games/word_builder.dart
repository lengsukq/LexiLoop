/// 单词拼图（WORD_BUILDER）的纯状态机。
///
/// 对应旧版 `app/(main)/games/word-builder.tsx`：
/// 给出中文释义，从打乱的字母池里点出（或拖出）英文单词。
///
/// **判定规则与旧版逐条一致**：字母必须全部用完才能提交；提交结果忽略大小写；
/// 提交错误 → 记一次失误并清空已拼字母；点「不认识」→ 揭示答案、暂停计时、
/// 记一次失误，确认后该题记为未完成。
///
/// **简化的只是交互**：旧版同时支持点按与指针拖动（`pointermove` +
/// `elementFromPoint`），这里只保留点按。拖动在 Flutter 里需要自定义
/// 手势与命中测试，收益仅是手感，且旧版的拖动实现（全局 pointermove 监听）
/// 本身是 `docs/CLEAN_CODE_BASELINE.md` 里「命令式 DOM 操作」的代表。
library;

import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';

/// 单词拼图的状态。
class WordBuilderState {
  /// 以各字段构造。
  const new({
    required this.questions,
    required this.core,
    this.selectedIds = const <String>[],
    this.itemElapsedMs = 0,
    this.revealed = false,
    this.wrong = false,
  });

  /// 全部题目。
  final List<GameQuestion> questions;

  /// 计分内核。
  final GameCoreState core;

  /// 已选字母块 id（顺序即拼写顺序）。
  final List<String> selectedIds;

  /// 当前题已过去的时间（揭示答案期间不计时）。
  final int itemElapsedMs;

  /// 是否已揭示答案。
  final bool revealed;

  /// 上次提交是否错误（界面据此抖动反馈）。
  final bool wrong;

  /// 当前题目；已结束时为 `null`。
  GameQuestion? get current =>
      core.isFinished || core.progress.index >= questions.length
      ? null
      : questions[core.progress.index];

  /// 当前已拼出的文本。
  String get answer {
    final question = current;
    if (question == null) return '';
    return joinLetters(question.word.letters, selectedIds);
  }

  /// 是否已用完所有字母块（旧版据此启用提交按钮）。
  bool get isComplete {
    final question = current;
    return question != null &&
        selectedIds.length == question.word.letters.length;
  }

  /// 复制并覆盖部分字段。
  WordBuilderState copyWith({
    GameCoreState? core,
    List<String>? selectedIds,
    int? itemElapsedMs,
    bool? revealed,
    bool? wrong,
  }) {
    return WordBuilderState(
      questions: questions,
      core: core ?? this.core,
      selectedIds: selectedIds ?? this.selectedIds,
      itemElapsedMs: itemElapsedMs ?? this.itemElapsedMs,
      revealed: revealed ?? this.revealed,
      wrong: wrong ?? this.wrong,
    );
  }
}

/// 单词拼图的动作。
sealed class WordBuilderAction {
  /// 供子类继承。
  const new();
}

/// 开始计时。
final class StartWordBuilder extends WordBuilderAction {
  /// 构造。
  const new();
}

/// 时间前进（揭示答案期间被忽略，等价于暂停倒计时）。
final class TickWordBuilder extends WordBuilderAction {
  /// 以增量构造。
  const new(this.deltaMs);

  /// 时间增量（毫秒）。
  final int deltaMs;
}

/// 从字母池选入一个字母块。
final class SelectLetter extends WordBuilderAction {
  /// 以字母块 id 构造。
  const new(this.letterId);

  /// 字母块 id。
  final String letterId;
}

/// 把已选字母块退回字母池。
final class DeselectLetter extends WordBuilderAction {
  /// 以字母块 id 构造。
  const new(this.letterId);

  /// 字母块 id。
  final String letterId;
}

/// 清空已拼字母。
final class ClearLetters extends WordBuilderAction {
  /// 构造。
  const new();
}

/// 提交作答。
final class SubmitWord extends WordBuilderAction {
  /// 构造。
  const new();
}

/// 点「不认识」，揭示答案。
final class RevealWord extends WordBuilderAction {
  /// 构造。
  const new();
}

/// 确认已看过答案，本题记为未完成。
final class ConfirmRevealed extends WordBuilderAction {
  /// 构造。
  const new();
}

/// 反馈结束，进入下一题。
final class AdvanceWordBuilder extends WordBuilderAction {
  /// 构造。
  const new();
}

/// 建一局单词拼图。
WordBuilderState startWordBuilder({
  required GamePlan plan,
  required List<GameQuestion> questions,
}) {
  return WordBuilderState(
    questions: questions,
    core: GameCoreState(plan: plan),
  );
}

/// 状态机入口。
WordBuilderState wordBuilderNext(
  WordBuilderState state,
  WordBuilderAction action,
) {
  return switch (action) {
    StartWordBuilder() => state.copyWith(core: state.core.start()),
    TickWordBuilder(:final deltaMs) => _tick(state, deltaMs),
    SelectLetter(:final letterId) => _select(state, letterId),
    DeselectLetter(:final letterId) => _deselect(state, letterId),
    ClearLetters() => state.copyWith(
      selectedIds: const <String>[],
      wrong: false,
    ),
    SubmitWord() => _submit(state),
    RevealWord() => _reveal(state),
    ConfirmRevealed() => _confirmRevealed(state),
    AdvanceWordBuilder() => _advance(state),
  };
}

WordBuilderState _tick(WordBuilderState state, int deltaMs) {
  if (state.revealed) return state;
  return state.copyWith(
    core: state.core.tick(deltaMs: deltaMs),
    itemElapsedMs: state.itemElapsedMs + deltaMs,
  );
}

WordBuilderState _select(WordBuilderState state, String letterId) {
  if (!state.core.isPlaying || state.revealed) return state;
  final question = state.current;
  if (question == null) return state;
  final available = question.word.letters.any((tile) => tile.id == letterId);
  if (!available || state.selectedIds.contains(letterId)) return state;
  if (state.selectedIds.length >= question.word.letters.length) return state;
  return state.copyWith(
    selectedIds: <String>[...state.selectedIds, letterId],
    wrong: false,
  );
}

WordBuilderState _deselect(WordBuilderState state, String letterId) {
  if (!state.core.isPlaying || state.revealed) return state;
  if (!state.selectedIds.contains(letterId)) return state;
  return state.copyWith(
    selectedIds: <String>[
      for (final id in state.selectedIds)
        if (id != letterId) id,
    ],
    wrong: false,
  );
}

WordBuilderState _submit(WordBuilderState state) {
  final question = state.current;
  if (question == null || !state.core.isPlaying || state.revealed) return state;
  if (!state.isComplete) return state;
  if (lettersMatchTerm(answer: state.answer, term: question.word.term)) {
    return state.copyWith(
      core: state.core.recordCorrect(
        itemId: question.itemId,
        answerMs: state.itemElapsedMs,
      ),
    );
  }
  return state.copyWith(
    core: state.core.recordMistake(itemId: question.itemId),
    selectedIds: const <String>[],
    wrong: true,
  );
}

WordBuilderState _reveal(WordBuilderState state) {
  final question = state.current;
  if (question == null || !state.core.isPlaying || state.revealed) return state;
  return state.copyWith(
    core: state.core.recordMistake(itemId: question.itemId),
    revealed: true,
  );
}

WordBuilderState _confirmRevealed(WordBuilderState state) {
  final question = state.current;
  if (question == null || !state.revealed) return state;
  return state.copyWith(
    core: state.core.recordMissed(
      itemId: question.itemId,
      answerMs: state.itemElapsedMs,
    ),
    revealed: false,
  );
}

WordBuilderState _advance(WordBuilderState state) {
  if (state.current == null) return state;
  return WordBuilderState(
    questions: state.questions,
    core: state.core.advance(),
  );
}
