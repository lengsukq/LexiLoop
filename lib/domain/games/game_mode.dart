/// 练习模式的枚举与规则表。
///
/// 对应旧版 `modules/games/modes.ts`（模式常量）、`modules/games/service.ts`
/// 的 `GAME_CONFIGS` 与 `modules/matching/service.ts` 的对数/时限边界。
///
/// **为什么规则表放在 domain**：旧版把题量、时限、题型、任务类型、计分权重
/// 分散在 `games/service.ts`、`games/completion.ts`、`matching/service.ts`
/// 三处，改一个数值要在三个文件里找。这里把「一个模式怎么玩」收敛成
/// [GameModeRules] 一个值对象，界面与服务都只读它。
library;

import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/games/game_constants.dart';

/// 小游戏、配对与音标训练的模式。
///
/// [wire] 与旧版 `GAME_MODES` 及排行榜里的 `game_mode` 列逐字对应，
/// 保证旧备份导入后历史高分仍能按模式归类。
enum GameMode {
  /// 单词拼图：按释义从字母池拼出单词。
  wordBuilder('WORD_BUILDER'),

  /// 词汇地鼠：按释义锤中冒头的正确单词。
  whackAMole('WHACK_A_MOLE'),

  /// 单词堆堆乐：按释义点选滚动词块。
  wordStack('WORD_STACK'),

  /// 词汇俄罗斯方块：按释义点中下落的正确单词。
  wordTetris('WORD_TETRIS'),

  /// 限时词汇配对。
  match('MATCH'),

  /// 音标辨音训练。
  phonetics('PHONETICS');

  new(this.wire);

  /// 数据库与备份 JSON 中的稳定标识。
  final String wire;

  /// 该模式是否属于「四个小游戏」（配对与音标有各自的会话与结算规则）。
  bool get isMiniGame => this != GameMode.match && this != GameMode.phonetics;

  /// 会话来源标识：小游戏带 `GAME_` 前缀。
  ///
  /// 前缀必须与 `ReviewService._isExcludedSource` 的判定一致——
  /// 小游戏与配对不参与自适应插题，否则答错会往游戏会话里插复习题。
  String get sourceType => switch (this) {
    GameMode.match => 'MATCH_GAME',
    GameMode.phonetics => phoneticTrainingSourceType,
    _ => 'GAME_$wire',
  };
}

/// 词条在游戏候选池里的优先级。
///
/// 与旧版 `practice/candidates.ts` 的 `PracticePriority` 一致：
/// 活跃错词 > 近期忘记/模糊 > 到期 > 普通。
enum GamePriority {
  /// 活跃错词。
  wrong('WRONG'),

  /// 近 14 天出现过 AGAIN 或 HARD。
  recentMistake('RECENT_MISTAKE'),

  /// 已到期复习。
  due('DUE'),

  /// 普通候选。
  normal('NORMAL');

  new(this.wire);

  /// 稳定标识（旧版同名）。
  final String wire;
}

/// 速度加减分规则。
class GameSpeedRules {
  /// 以各阈值构造。
  const new({
    required this.fastAnswerMs,
    required this.fastAnswerBonus,
    required this.slowAnswerMs,
    required this.slowAnswerPenalty,
  });

  /// 快答阈值（毫秒）。
  final int fastAnswerMs;

  /// 快答奖励分值。
  final int fastAnswerBonus;

  /// 慢答阈值（毫秒）。
  final int slowAnswerMs;

  /// 慢答扣分分值。
  final int slowAnswerPenalty;
}

/// 一局的计分权重。
///
/// 旧版 `games/completion.ts` 与 `matching/service.ts` 各有一套；
/// 收敛后四个小游戏共用 [gameBasePoints] 一组，配对与音标各用自己的一组，
/// 但**只有一套计算函数**（见 `scoring.dart`）。
class GameScoreRules {
  /// 以各权重构造。
  const new({
    required this.basePoints,
    required this.comboStep,
    required this.comboCap,
    required this.mistakePenalty,
    required this.speed,
  });

  /// 一次答对的基础分。
  final int basePoints;

  /// 每级连击的加分步长。
  final int comboStep;

  /// 连击加成的封顶级数。
  final int comboCap;

  /// 每次失误的罚分。
  final int mistakePenalty;

  /// 速度加减分规则。
  final GameSpeedRules speed;
}

/// 剩余时间换分规则。
class GameTimeBonusRules {
  /// 以各字段构造。
  const new({required this.divisorMs, required this.cap});

  /// 换算分母（毫秒）：`remainingMs ~/ divisorMs` 即得分。
  ///
  /// `0` 表示该模式不按剩余时间加分。
  final int divisorMs;

  /// 换分上限。
  final int cap;
}

/// 一局的会话与会话题目配置。
class GameSessionRules {
  /// 以各字段构造。
  const new({
    required this.sessionType,
    required this.questionType,
    required this.taskType,
    required this.itemCount,
    required this.durationSeconds,
  });

  /// 落库的 `study_sessions.session_type`。
  final StudyMode sessionType;

  /// 会话题目的题型（复习日志里记录的题型）。
  final QuestionType questionType;

  /// 会话题目的任务类型。
  final StudyTaskType taskType;

  /// 题量。
  final int itemCount;

  /// 时限（秒）。
  final int durationSeconds;
}

/// 一个模式的全部规则。
class GameModeRules {
  /// 以各字段构造。
  const new({
    required this.score,
    required this.session,
    required this.timeBonus,
  });

  /// 计分权重。
  final GameScoreRules score;

  /// 会话配置。
  final GameSessionRules session;

  /// 剩余时间换分规则。
  final GameTimeBonusRules timeBonus;

  /// 时限（毫秒）。
  int get durationMs => session.durationSeconds * secondMs;
}

/// 所有模式共用的单题速度规则。
///
/// 配对与音标另有整体倒计时，但单题层面的快答奖励仍然适用——
/// 旧版 `useActiveStopwatch` 对三者一视同仁地测量单题耗时。
const GameSpeedRules _speedRules = GameSpeedRules(
  fastAnswerMs: gameFastAnswerMs,
  fastAnswerBonus: gameFastAnswerBonus,
  slowAnswerMs: gameSlowAnswerMs,
  slowAnswerPenalty: gameSlowAnswerPenalty,
);

/// 不计剩余时间的模式。
const GameTimeBonusRules _noTimeBonus = GameTimeBonusRules(
  divisorMs: 0,
  cap: 0,
);

/// 各模式的规则表。
///
/// 数值全部来自 `game_constants.dart`（迁入 `core/constants.dart` 后即同一出处），
/// 与旧版 `GAME_CONFIGS` 逐条对应；`match` 的对数与时限边界由
/// `matching_service.dart` 用 `matching*` 常量夹取。
const Map<GameMode, GameModeRules> gameModeRules = <GameMode, GameModeRules>{
  GameMode.wordBuilder: GameModeRules(
    score: GameScoreRules(
      basePoints: gameBasePoints,
      comboStep: gameComboStep,
      comboCap: gameComboCap,
      mistakePenalty: gameMistakePenalty,
      speed: _speedRules,
    ),
    session: GameSessionRules(
      sessionType: StudyMode.spelling,
      questionType: QuestionType.zhToEnSpelling,
      taskType: StudyTaskType.spelling,
      itemCount: wordBuilderItemCount,
      durationSeconds: wordBuilderDurationSeconds,
    ),
    timeBonus: _noTimeBonus,
  ),
  GameMode.whackAMole: GameModeRules(
    score: GameScoreRules(
      basePoints: gameBasePoints,
      comboStep: gameComboStep,
      comboCap: gameComboCap,
      mistakePenalty: gameMistakePenalty,
      speed: _speedRules,
    ),
    session: GameSessionRules(
      sessionType: StudyMode.daily,
      questionType: QuestionType.zhToEnChoice,
      taskType: StudyTaskType.review,
      itemCount: whackAMoleItemCount,
      durationSeconds: whackAMoleDurationSeconds,
    ),
    timeBonus: _noTimeBonus,
  ),
  GameMode.wordStack: GameModeRules(
    score: GameScoreRules(
      basePoints: gameBasePoints,
      comboStep: gameComboStep,
      comboCap: gameComboCap,
      mistakePenalty: gameMistakePenalty,
      speed: _speedRules,
    ),
    session: GameSessionRules(
      sessionType: StudyMode.daily,
      questionType: QuestionType.zhToEnChoice,
      taskType: StudyTaskType.review,
      itemCount: wordStackItemCount,
      durationSeconds: wordStackDurationSeconds,
    ),
    timeBonus: _noTimeBonus,
  ),
  GameMode.wordTetris: GameModeRules(
    score: GameScoreRules(
      basePoints: gameBasePoints,
      comboStep: gameComboStep,
      comboCap: gameComboCap,
      mistakePenalty: gameMistakePenalty,
      speed: _speedRules,
    ),
    session: GameSessionRules(
      sessionType: StudyMode.daily,
      questionType: QuestionType.zhToEnChoice,
      taskType: StudyTaskType.review,
      itemCount: wordTetrisItemCount,
      durationSeconds: wordTetrisDurationSeconds,
    ),
    timeBonus: _noTimeBonus,
  ),
  GameMode.match: GameModeRules(
    score: GameScoreRules(
      basePoints: matchBasePoints,
      comboStep: matchComboStep,
      comboCap: gameComboCap,
      mistakePenalty: matchMistakePenalty,
      speed: _speedRules,
    ),
    session: GameSessionRules(
      sessionType: StudyMode.wrongWords,
      questionType: QuestionType.enToZhChoice,
      taskType: StudyTaskType.newWord,
      itemCount: matchingDefaultPairCount,
      durationSeconds: matchingDefaultDurationSeconds,
    ),
    timeBonus: GameTimeBonusRules(
      divisorMs: matchRemainingTimeDivisorMs,
      cap: matchRemainingTimeBonusCap,
    ),
  ),
  GameMode.phonetics: GameModeRules(
    score: GameScoreRules(
      basePoints: phoneticBasePoints,
      comboStep: phoneticComboStep,
      comboCap: gameComboCap,
      mistakePenalty: phoneticMistakePenalty,
      speed: _speedRules,
    ),
    session: GameSessionRules(
      sessionType: StudyMode.listening,
      questionType: QuestionType.listeningSpelling,
      taskType: StudyTaskType.listening,
      itemCount: phoneticItemCount,
      durationSeconds: phoneticDurationSeconds,
    ),
    timeBonus: _noTimeBonus,
  ),
};

/// 读取某个模式的规则；未登记的模式回退到词汇地鼠（仅防御性兜底）。
GameModeRules rulesFor(GameMode mode) =>
    gameModeRules[mode] ?? gameModeRules[GameMode.whackAMole]!;
