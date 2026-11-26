/// 音标辨音训练的状态机。
///
/// 对应旧版 `app/(main)/phonetics/use-phonetic-game.ts`：
/// 每题一个题型（听音选音标 / 看音标选例词 / 看单词选音标），
/// 答对进下一题，答错停留在本题重选，跳过则本题记为未完成。
///
/// **与旧版的差异（有意）**：
/// 1. 旧版答错后 520ms 自动清掉错误标记，靠 `setTimeout` 驱动；这里改为
///    显式的 [ContinuePhonetic]，答错时先清标记、答对/跳过时进下一题；
/// 2. 旧版跳过直接进下一题，用户看不到正确答案；这里跳过会先展示解析，
///    再由 [ContinuePhonetic] 推进——练音标的意义就在于看到正确的那一个。
library;

import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/phonetics/selection.dart';

/// 音标训练的状态。
class PhoneticQuizState {
  /// 以各字段构造。
  const new({
    required this.questions,
    required this.core,
    this.itemElapsedMs = 0,
    this.selected,
    this.revealed = false,
  });

  /// 全部题目。
  final List<PhoneticQuestion> questions;

  /// 计分内核。
  final GameCoreState core;

  /// 当前题已过去的时间。
  final int itemElapsedMs;

  /// 当前题已选中的选项（答错时用于高亮）。
  final String? selected;

  /// 当前题是否已揭示答案（答对或跳过）。
  final bool revealed;

  /// 当前题目；已结束时为 `null`。
  PhoneticQuestion? get current =>
      core.isFinished || core.progress.index >= questions.length
      ? null
      : questions[core.progress.index];

  /// 当前题是否已作答错误但尚未清除标记。
  bool get hasWrongSelection => selected != null && !revealed;

  /// 复制并覆盖部分字段。
  PhoneticQuizState copyWith({
    GameCoreState? core,
    int? itemElapsedMs,
    String? selected,
    bool clearSelected = false,
    bool? revealed,
  }) {
    return PhoneticQuizState(
      questions: questions,
      core: core ?? this.core,
      itemElapsedMs: itemElapsedMs ?? this.itemElapsedMs,
      selected: clearSelected ? null : (selected ?? this.selected),
      revealed: revealed ?? this.revealed,
    );
  }
}

/// 音标训练的动作。
sealed class PhoneticQuizAction {
  /// 供子类继承。
  const new();
}

/// 开始计时。
final class StartPhoneticQuiz extends PhoneticQuizAction {
  /// 构造。
  const new();
}

/// 时间前进。
final class TickPhoneticQuiz extends PhoneticQuizAction {
  /// 以增量构造。
  const new(this.deltaMs);

  /// 时间增量（毫秒）。
  final int deltaMs;
}

/// 选择一个选项。
final class ChoosePhonetic extends PhoneticQuizAction {
  /// 以选项文本构造。
  const new(this.choice);

  /// 被选中的选项。
  final String choice;
}

/// 跳过本题。
final class SkipPhonetic extends PhoneticQuizAction {
  /// 构造。
  const new();
}

/// 解析看完，继续（答错时清标记，答对/跳过时进下一题）。
final class ContinuePhonetic extends PhoneticQuizAction {
  /// 构造。
  const new();
}

/// 建一局音标训练。
PhoneticQuizState startPhoneticQuiz({
  required GamePlan plan,
  required List<PhoneticQuestion> questions,
}) {
  return PhoneticQuizState(
    questions: questions,
    core: GameCoreState(plan: plan),
  );
}

/// 状态机入口。
PhoneticQuizState phoneticQuizNext(
  PhoneticQuizState state,
  PhoneticQuizAction action,
) {
  return switch (action) {
    StartPhoneticQuiz() => state.copyWith(core: state.core.start()),
    TickPhoneticQuiz(:final deltaMs) => _tick(state, deltaMs),
    ChoosePhonetic(:final choice) => _choose(state, choice),
    SkipPhonetic() => _skip(state),
    ContinuePhonetic() => _continue(state),
  };
}

/// 生成逐题作答记录（顺序与题目一致）。
List<GameAnswerRecord> phoneticAnswerRecords(PhoneticQuizState state) =>
    state.core.answerRecords(<GameQuestion>[
      for (final question in state.questions) question.base,
    ]);

PhoneticQuizState _tick(PhoneticQuizState state, int deltaMs) {
  if (state.revealed) return state;
  return state.copyWith(
    core: state.core.tick(deltaMs: deltaMs),
    itemElapsedMs: state.itemElapsedMs + deltaMs,
  );
}

PhoneticQuizState _choose(PhoneticQuizState state, String choice) {
  final question = state.current;
  if (question == null || !state.core.isPlaying) return state;
  if (state.revealed || state.hasWrongSelection) return state;
  if (choice != question.answer) {
    return state.copyWith(
      core: state.core.recordMistake(itemId: question.base.itemId),
      selected: choice,
    );
  }
  return state.copyWith(
    core: state.core.recordCorrect(
      itemId: question.base.itemId,
      answerMs: state.itemElapsedMs,
    ),
    selected: choice,
    revealed: true,
  );
}

PhoneticQuizState _skip(PhoneticQuizState state) {
  final question = state.current;
  if (question == null || !state.core.isPlaying) return state;
  if (state.revealed) return state;
  return state.copyWith(
    core: state.core.recordMissed(
      itemId: question.base.itemId,
      answerMs: state.itemElapsedMs,
    ),
    revealed: true,
  );
}

PhoneticQuizState _continue(PhoneticQuizState state) {
  final question = state.current;
  if (question == null) return state;
  if (!state.revealed) {
    return state.copyWith(clearSelected: true);
  }
  return PhoneticQuizState(
    questions: state.questions,
    core: state.core.advance(),
  );
}
