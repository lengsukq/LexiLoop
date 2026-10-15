/// 词汇俄罗斯方块（WORD_TETRIS）的纯状态机。
///
/// 对应旧版 `app/(main)/games/word-tetris.tsx`：
/// 候选词从四条轨道分别下落，点中正确的那个即可消掉；点错记一次失误，
/// 方块继续下落；方块落到底部就往上堆一层，堆到
/// [wordTetrisDangerCap] 层本局结束。
///
/// **判定规则与旧版逐条一致**：正确方块落地 → 该题未完成并进入下一题；
/// 错误方块落地 → 只加一层，不影响本题；点中正确方块 → 该题解决且消一层；
/// 堆满 → 结束本局。下落时长是 [wordTetrisFallMinMs] 起的随机值，
/// 与旧版一样由随机源决定，但**在开局时一次性生成**，因此状态机可复现。
///
/// **简化的只是视觉**：旧版用 `tetris-fall` 关键帧做连续位移，
/// 这里把「剩余下落时间」暴露给界面，由界面按比例换算纵向位置；
/// 堆叠层用静态条块表示，不做 `tetris-stack-in` 的入场动画。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/games/game_core.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/review/question_payload.dart';

/// 一个方块的下落规格（开局时由随机源生成）。
class TetrisBlockSpec {
  /// 以各字段构造。
  const new({required this.word, required this.column, required this.fallMs});

  /// 方块上的候选词。
  final String word;

  /// 轨道号（0 起）。
  final int column;

  /// 下落总时长（毫秒）。
  final int fallMs;
}

/// 运行中的方块。
class TetrisBlock {
  /// 以各字段构造。
  const new({
    required this.word,
    required this.column,
    required this.fallMs,
    required this.remainingMs,
    this.resolved = false,
    this.smashed = false,
  });

  /// 方块上的候选词。
  final String word;

  /// 轨道号（0 起）。
  final int column;

  /// 下落总时长（毫秒）。
  final int fallMs;

  /// 剩余下落时间（毫秒）。
  final int remainingMs;

  /// 是否已落地（落地的方块不再参与判定）。
  final bool resolved;

  /// 是否被点中消除。
  final bool smashed;

  /// 是否已经落地。
  bool get landed => remainingMs <= 0;

  /// 已下落比例（0–1），供界面换算纵向位置。
  double get progress {
    if (fallMs <= 0) return 1;
    final done = fallMs - remainingMs;
    if (done <= 0) return 0;
    return done >= fallMs ? 1 : done / fallMs;
  }

  /// 复制并覆盖部分字段。
  TetrisBlock copyWith({int? remainingMs, bool? resolved, bool? smashed}) {
    return TetrisBlock(
      word: word,
      column: column,
      fallMs: fallMs,
      remainingMs: remainingMs ?? this.remainingMs,
      resolved: resolved ?? this.resolved,
      smashed: smashed ?? this.smashed,
    );
  }
}

/// 题面与当前题的方块。
class TetrisBoard {
  /// 以各字段构造。
  const new({required this.layouts, required this.blocks});

  /// 每题的方块规格（下标与题目下标一致）。
  final List<List<TetrisBlockSpec>> layouts;

  /// 当前题的运行中方块。
  final List<TetrisBlock> blocks;

  /// 取出第 [index] 题的方块。
  List<TetrisBlock> blocksAt(int index) {
    if (index < 0 || index >= layouts.length) return const <TetrisBlock>[];
    return <TetrisBlock>[
      for (final spec in layouts[index])
        TetrisBlock(
          word: spec.word,
          column: spec.column,
          fallMs: spec.fallMs,
          remainingMs: spec.fallMs,
        ),
    ];
  }

  /// 推进下落时间。
  TetrisBoard decay(int deltaMs) {
    return TetrisBoard(
      layouts: layouts,
      blocks: <TetrisBlock>[
        for (final block in blocks)
          if (block.resolved)
            block
          else
            block.copyWith(remainingMs: block.remainingMs - deltaMs),
      ],
    );
  }

  /// 把某个词块的方块标记为已消除。
  TetrisBoard smash(String word) => _mark(word, smashed: true);

  /// 把某个词块的方块标记为已落地。
  TetrisBoard land(String word) => _mark(word, resolved: true);

  TetrisBoard _mark(String word, {bool? smashed, bool? resolved}) {
    return TetrisBoard(
      layouts: layouts,
      blocks: <TetrisBlock>[
        for (final block in blocks)
          if (block.word == word)
            block.copyWith(smashed: smashed, resolved: resolved)
          else
            block,
      ],
    );
  }
}

/// 按随机源生成一道题的方块规格。
List<TetrisBlockSpec> buildTetrisLayout({
  required List<String> choices,
  required double Function() random,
}) {
  final columns = shuffleWith(<int>[
    for (var index = 0; index < wordTetrisColumnCount; index += 1) index,
  ], random);
  final specs = <TetrisBlockSpec>[];
  for (var index = 0; index < choices.length; index += 1) {
    final spread = (random() * wordTetrisFallSpreadMs).round();
    specs.add(
      TetrisBlockSpec(
        word: choices[index],
        column: columns[index % columns.length],
        fallMs: wordTetrisFallMinMs + spread,
      ),
    );
  }
  return specs;
}

/// 俄罗斯方块的状态。
class WordTetrisState {
  /// 以各字段构造。
  const new({
    required this.questions,
    required this.board,
    required this.core,
    this.danger = 0,
    this.shakingWord,
    this.itemElapsedMs = 0,
  });

  /// 全部题目。
  final List<GameQuestion> questions;

  /// 题面与方块。
  final TetrisBoard board;

  /// 计分内核。
  final GameCoreState core;

  /// 已堆叠层数。
  final int danger;

  /// 上次点错的方块（界面据此抖动）。
  final String? shakingWord;

  /// 当前题已过去的时间。
  final int itemElapsedMs;

  /// 当前题目；已结束时为 `null`。
  GameQuestion? get current =>
      core.isFinished || core.progress.index >= questions.length
      ? null
      : questions[core.progress.index];

  /// 堆叠是否已满。
  bool get isStackFull => danger >= wordTetrisDangerCap;

  /// 复制并覆盖部分字段。
  WordTetrisState copyWith({
    TetrisBoard? board,
    GameCoreState? core,
    int? danger,
    String? shakingWord,
    bool clearShaking = false,
    int? itemElapsedMs,
  }) {
    return WordTetrisState(
      questions: questions,
      board: board ?? this.board,
      core: core ?? this.core,
      danger: danger ?? this.danger,
      shakingWord: clearShaking ? null : (shakingWord ?? this.shakingWord),
      itemElapsedMs: itemElapsedMs ?? this.itemElapsedMs,
    );
  }
}

/// 俄罗斯方块的动作。
sealed class WordTetrisAction {
  /// 供子类继承。
  const new();
}

/// 开始计时。
final class StartWordTetris extends WordTetrisAction {
  /// 构造。
  const new();
}

/// 时间前进（方块随之下落）。
final class TickWordTetris extends WordTetrisAction {
  /// 以增量构造。
  const new(this.deltaMs);

  /// 时间增量（毫秒）。
  final int deltaMs;
}

/// 点选一个下落的方块。
final class TapTetrisBlock extends WordTetrisAction {
  /// 以方块文本构造。
  const new(this.word);

  /// 被点中的方块文本。
  final String word;
}

/// 清除抖动反馈。
final class ClearTetrisShake extends WordTetrisAction {
  /// 构造。
  const new();
}

/// 反馈结束，进入下一题。
final class AdvanceWordTetris extends WordTetrisAction {
  /// 构造。
  const new();
}

/// 建一局俄罗斯方块（下落时长与轨道由注入的随机源分配）。
WordTetrisState startWordTetris({
  required GamePlan plan,
  required List<GameQuestion> questions,
  required double Function() random,
}) {
  final layouts = <List<TetrisBlockSpec>>[
    for (final question in questions)
      buildTetrisLayout(choices: question.choices.options, random: random),
  ];
  final board = TetrisBoard(layouts: layouts, blocks: const <TetrisBlock>[]);
  return WordTetrisState(
    questions: questions,
    board: TetrisBoard(layouts: layouts, blocks: board.blocksAt(0)),
    core: GameCoreState(plan: plan),
  );
}

/// 状态机入口。
WordTetrisState wordTetrisNext(WordTetrisState state, WordTetrisAction action) {
  return switch (action) {
    StartWordTetris() => state.copyWith(core: state.core.start()),
    TickWordTetris(:final deltaMs) => _tick(state, deltaMs),
    TapTetrisBlock(:final word) => _tap(state, word),
    ClearTetrisShake() => state.copyWith(clearShaking: true),
    AdvanceWordTetris() => advanceWordTetris(state),
  };
}

/// 进入下一题并重建方块（结算与超时路径也走这里）。
WordTetrisState advanceWordTetris(WordTetrisState state) {
  if (state.current == null) return state;
  final core = state.core.advance();
  return WordTetrisState(
    questions: state.questions,
    board: TetrisBoard(
      layouts: state.board.layouts,
      blocks: state.board.blocksAt(core.progress.index),
    ),
    core: core,
    danger: state.danger,
  );
}

WordTetrisState _tick(WordTetrisState state, int deltaMs) {
  final core = state.core.tick(deltaMs: deltaMs);
  if (core.isFinished) return state.copyWith(core: core);
  final next = state.copyWith(
    core: core,
    itemElapsedMs: state.itemElapsedMs + deltaMs,
    board: state.board.decay(deltaMs),
  );
  return _resolveLandings(next);
}

WordTetrisState _tap(WordTetrisState state, String word) {
  final question = state.current;
  if (question == null || !state.core.isPlaying) return state;
  final block = _blockFor(state, word);
  if (block == null || block.resolved) return state;
  if (word == question.answer) {
    final danger = state.danger > 0 ? state.danger - 1 : 0;
    return state.copyWith(
      core: state.core.recordCorrect(
        itemId: question.itemId,
        answerMs: state.itemElapsedMs,
      ),
      board: state.board.smash(word),
      danger: danger,
    );
  }
  return state.copyWith(
    core: state.core.recordMistake(itemId: question.itemId),
    shakingWord: word,
  );
}

/// 处理本帧落地的方块。
///
/// 命中正确方块时**立刻返回**：此时已经进入下一题，继续遍历上一题的
/// 其余方块会把它们的落地也记到新题的堆叠上（同一帧内多个方块同时落地
/// 时必然发生）。
WordTetrisState _resolveLandings(WordTetrisState state) {
  var next = state;
  for (final block in state.board.blocks) {
    if (!block.landed || block.resolved) continue;
    next = next.copyWith(
      board: next.board.land(block.word),
      danger: next.danger + 1,
    );
    if (next.isStackFull) return next.copyWith(core: next.core.finish());
    final question = next.current;
    if (question == null || block.word != question.answer) continue;
    return advanceWordTetris(
      next.copyWith(
        core: next.core.recordMissed(
          itemId: question.itemId,
          answerMs: next.itemElapsedMs,
        ),
      ),
    );
  }
  return next;
}

TetrisBlock? _blockFor(WordTetrisState state, String word) {
  for (final block in state.board.blocks) {
    if (block.word == word) return block;
  }
  return null;
}
