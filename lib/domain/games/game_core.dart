/// 六个小游戏共用的计分与进度内核。
///
/// **为什么要有这个内核**：旧版把「连击 / 最高连击 / 失误计数 / 逐题耗时 /
/// 进度 / 倒计时」这一整套逻辑写在 `use-game-scoring.ts` 与
/// `use-game-countdown.ts` 两个 React Hook 里，再由 `games/page.tsx`（543 行）
/// 用 12 个 `useState` 串起来；规则因此无法单测，只能靠点界面验证。
/// 这里把同一套规则收敛成一个**无副作用**的状态机：
/// 不读时钟、不读数据库、不调 TTS，时间以 [GameCoreState.tick] 的增量传入。
///
/// 四个游戏各自的状态机（`whack_a_mole.dart` 等）持有本内核，
/// 只额外保存「本游戏特有」的呈现状态（地鼠冒头、字母块、方块下落位置…）。
library;

import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/domain/games/game_mode.dart';
import 'package:lexiloop/domain/games/game_question.dart';
import 'package:lexiloop/domain/games/scoring.dart';

/// 一局的生命周期。
enum GamePhase {
  /// 准备中，尚未开始计时。
  ready,

  /// 进行中。
  playing,

  /// 已结束（时间到、题做完或堆叠满）。
  finished,
}

/// 单个词条的作答结果。
enum GameOutcome {
  /// 一次答对（该题从未失误）。
  firstTry,

  /// 失误后纠正完成。
  recovered,

  /// 未完成（超时、跳过、堆满）。
  missed,
}

/// 一局的静态计划。
class GamePlan {
  /// 以各字段构造。
  const new({
    required this.mode,
    required this.itemCount,
    required this.durationMs,
  });

  /// 模式。
  final GameMode mode;

  /// 题量。
  final int itemCount;

  /// 时限（毫秒）。
  final int durationMs;
}

/// 按模式生成计划；可覆盖题量与时限（配对与音标由用户配置）。
GamePlan gamePlanFor(GameMode mode, {int? itemCount, int? durationSeconds}) {
  final rules = rulesFor(mode).session;
  final seconds = durationSeconds ?? rules.durationSeconds;
  return GamePlan(
    mode: mode,
    itemCount: itemCount ?? rules.itemCount,
    durationMs: seconds * secondMs,
  );
}

/// 一局的进度与计时。
class GameProgress {
  /// 以各字段构造。
  const new({this.phase = GamePhase.ready, this.index = 0, this.elapsedMs = 0});

  /// 当前阶段。
  final GamePhase phase;

  /// 当前题号（0 起）。
  final int index;

  /// 已用时间（毫秒）。
  final int elapsedMs;

  /// 复制并覆盖部分字段。
  GameProgress copyWith({GamePhase? phase, int? index, int? elapsedMs}) {
    return GameProgress(
      phase: phase ?? this.phase,
      index: index ?? this.index,
      elapsedMs: elapsedMs ?? this.elapsedMs,
    );
  }
}

/// 一局的计分累计。
class GameTally {
  /// 以各字段构造。
  const new({
    this.score = 0,
    this.combo = 0,
    this.maxCombo = 0,
    this.mistakeCount = 0,
  });

  /// 当前得分（逐题累计，含罚分）。
  final int score;

  /// 当前连击。
  final int combo;

  /// 最高连击。
  final int maxCombo;

  /// 失误次数。
  final int mistakeCount;

  /// 复制并覆盖部分字段。
  GameTally copyWith({
    int? score,
    int? combo,
    int? maxCombo,
    int? mistakeCount,
  }) {
    return GameTally(
      score: score ?? this.score,
      combo: combo ?? this.combo,
      maxCombo: maxCombo ?? this.maxCombo,
      mistakeCount: mistakeCount ?? this.mistakeCount,
    );
  }
}

/// 逐题的作答记录。
class GameRecords {
  /// 以各字段构造。
  const new({
    this.solvedItemIds = const <int>{},
    this.mistakeItemIds = const <int>{},
    this.durationsMs = const <int, int>{},
  });

  /// 已解决的题目 ID。
  final Set<int> solvedItemIds;

  /// 出现过失误（含未完成）的题目 ID。
  final Set<int> mistakeItemIds;

  /// 逐题作答耗时。
  final Map<int, int> durationsMs;

  /// 复制并覆盖部分字段。
  GameRecords copyWith({
    Set<int>? solvedItemIds,
    Set<int>? mistakeItemIds,
    Map<int, int>? durationsMs,
  }) {
    return GameRecords(
      solvedItemIds: solvedItemIds ?? this.solvedItemIds,
      mistakeItemIds: mistakeItemIds ?? this.mistakeItemIds,
      durationsMs: durationsMs ?? this.durationsMs,
    );
  }

  /// 该题是否已解决。
  bool isSolved(int itemId) => solvedItemIds.contains(itemId);

  /// 该题是否出现过失误。
  bool hasMistake(int itemId) => mistakeItemIds.contains(itemId);
}

/// 提交给结算层的单题作答。
class GameAnswerRecord {
  /// 以各字段构造。
  const new({
    required this.itemId,
    required this.wordId,
    required this.solved,
    required this.hadMistake,
    required this.durationMs,
  });

  /// 会话题目 ID。
  final int itemId;

  /// 词条 ID。
  final int wordId;

  /// 是否答对。
  final bool solved;

  /// 是否出现过失误（含未完成）。
  final bool hadMistake;

  /// 本题耗时（毫秒）。
  final int durationMs;
}

/// 一局的计分与进度内核。
class GameCoreState {
  /// 以计划构造初始状态。
  const new({
    required this.plan,
    this.progress = const GameProgress(),
    this.tally = const GameTally(),
    this.records = const GameRecords(),
  });

  /// 静态计划。
  final GamePlan plan;

  /// 进度与计时。
  final GameProgress progress;

  /// 计分累计。
  final GameTally tally;

  /// 逐题记录。
  final GameRecords records;

  /// 剩余时间（毫秒，不小于 0）。
  int get remainingMs {
    final left = plan.durationMs - progress.elapsedMs;
    return left < 0 ? 0 : left;
  }

  /// 是否已结束。
  bool get isFinished => progress.phase == GamePhase.finished;

  /// 是否可以进行作答。
  bool get isPlaying => progress.phase == GamePhase.playing;

  /// 当前题是否是最后一题。
  bool get isLastItem => progress.index >= plan.itemCount - 1;

  /// 开始计时。
  GameCoreState start() =>
      _withProgress(progress.copyWith(phase: GamePhase.playing));

  /// 推进时间；时间耗尽即结束本局。
  GameCoreState tick({required int deltaMs}) {
    if (!isPlaying) return this;
    final elapsed = progress.elapsedMs + deltaMs;
    final expired = elapsed >= plan.durationMs;
    return _withProgress(
      progress.copyWith(
        elapsedMs: expired ? plan.durationMs : elapsed,
        phase: expired ? GamePhase.finished : null,
      ),
    );
  }

  /// 记录一次正确作答。
  GameCoreState recordCorrect({required int itemId, required int answerMs}) {
    if (!isPlaying) return this;
    final combo = tally.combo + 1;
    final gained = scoreForAnswer(
      isCorrect: true,
      comboCount: combo,
      elapsedMs: answerMs,
      mode: plan.mode,
    );
    return _copyWith(
      tally: tally.copyWith(
        score: tally.score + gained,
        combo: combo,
        maxCombo: combo > tally.maxCombo ? combo : tally.maxCombo,
      ),
      records: records.copyWith(
        solvedItemIds: <int>{...records.solvedItemIds, itemId},
        durationsMs: <int, int>{...records.durationsMs, itemId: answerMs},
      ),
    );
  }

  /// 记录一次失误（点错、选错、主动跳过）。
  GameCoreState recordMistake({required int itemId}) {
    if (!isPlaying) return this;
    final lost = scoreForAnswer(
      isCorrect: false,
      comboCount: 0,
      elapsedMs: 0,
      mode: plan.mode,
    );
    return _copyWith(
      tally: tally.copyWith(
        score: tally.score + lost,
        combo: 0,
        mistakeCount: tally.mistakeCount + 1,
      ),
      records: records.copyWith(
        mistakeItemIds: <int>{...records.mistakeItemIds, itemId},
      ),
    );
  }

  /// 只标记某题曾失误，不推高失误计数、不扣分、不清零连击。
  ///
  /// 对应旧版 `use-game-scoring.ts` 的 `flagMistakeItems`：配对游戏一次错配
  /// 涉及两张牌，只应记一次失误，但两张牌都要标成「曾失误」——
  /// 否则其中一张之后配对成功会被误判为「一次配对」。
  GameCoreState flagMistake({required int itemId}) {
    return _copyWith(
      records: records.copyWith(
        mistakeItemIds: <int>{...records.mistakeItemIds, itemId},
      ),
    );
  }

  /// 记录一次未完成（地鼠全部缩回、正确方块落地、时间耗尽前的跳过）。
  ///
  /// 与旧版一致：未完成**不**计入 `mistakeCount`（那只统计主动点错），
  /// 但会标记该题出现过失误并清零连击。
  GameCoreState recordMissed({required int itemId, required int answerMs}) {
    if (!isPlaying) return this;
    return _copyWith(
      tally: tally.copyWith(combo: 0),
      records: records.copyWith(
        mistakeItemIds: <int>{...records.mistakeItemIds, itemId},
        durationsMs: <int, int>{...records.durationsMs, itemId: answerMs},
      ),
    );
  }

  /// 推进到下一题；已是最后一题则结束本局。
  GameCoreState advance() {
    if (!isPlaying) return this;
    final next = progress.index + 1;
    if (next >= plan.itemCount) {
      return _withProgress(progress.copyWith(phase: GamePhase.finished));
    }
    return _withProgress(progress.copyWith(index: next));
  }

  /// 直接结束本局（时间到、堆叠满）。
  GameCoreState finish() {
    if (isFinished) return this;
    return _withProgress(progress.copyWith(phase: GamePhase.finished));
  }

  /// 某题的作答结果。
  GameOutcome outcomeFor(int itemId) {
    if (!records.isSolved(itemId)) return GameOutcome.missed;
    return records.hasMistake(itemId)
        ? GameOutcome.recovered
        : GameOutcome.firstTry;
  }

  /// 结算汇总。
  GameRoundSummary get summary {
    var recovered = 0;
    for (final itemId in records.solvedItemIds) {
      if (records.hasMistake(itemId)) recovered += 1;
    }
    final solved = records.solvedItemIds.length;
    return GameRoundSummary(
      answerScore: tally.score,
      firstTryCorrect: solved - recovered,
      recovered: recovered,
      missed: plan.itemCount - solved,
      mistakeCount: tally.mistakeCount,
      maxCombo: tally.maxCombo,
      elapsedMs: progress.elapsedMs,
      durationMs: plan.durationMs,
    );
  }

  /// 生成逐题作答记录（顺序与 [questions] 一致）。
  ///
  /// 未作答的题目按「未解决 + 有失误 + [fallbackDurationMs] 耗时」提交，
  /// 与旧版 `games/page.tsx` 的兜底一致——否则超时结束的题目会漏出结算。
  /// 配对游戏没有逐题计时，用平均耗时兜底（旧版同样是
  /// `round(elapsedMs / pairCount)`）。
  List<GameAnswerRecord> answerRecords(
    List<GameQuestion> questions, {
    int fallbackDurationMs = 0,
  }) {
    return <GameAnswerRecord>[
      for (final question in questions)
        GameAnswerRecord(
          itemId: question.itemId,
          wordId: question.wordId,
          solved: records.isSolved(question.itemId),
          hadMistake:
              records.hasMistake(question.itemId) ||
              !records.isSolved(question.itemId),
          durationMs:
              records.durationsMs[question.itemId] ?? fallbackDurationMs,
        ),
    ];
  }

  GameCoreState _copyWith({GameTally? tally, GameRecords? records}) {
    return GameCoreState(
      plan: plan,
      progress: progress,
      tally: tally ?? this.tally,
      records: records ?? this.records,
    );
  }

  GameCoreState _withProgress(GameProgress next) {
    return GameCoreState(
      plan: plan,
      progress: next,
      tally: tally,
      records: records,
    );
  }
}
