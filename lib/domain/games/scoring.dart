/// 小游戏、配对与音标训练**唯一**的计分实现。
///
/// **为什么必须只有一套**：`docs/CLEAN_CODE_BASELINE.md` 点名的重复是
/// 旧版 `modules/games/completion.ts` 与 `modules/matching/service.ts`
/// 各写了一份权重与算式，音标又在 `modules/phonetics/service.ts` 写了第三份。
/// 三处的差异（100/55/12/−20、120/70/15/−25+剩余时间、120/60/15/−20）
/// 没有任何理由，只是复制粘贴后各自漂移。本文件把差异收敛为
/// [GameScoreRules] 的四个参数，算式只有一份。
///
/// **纯函数**：不读时间、不读数据库、不用全局随机源。
/// 时间与随机都由调用方作为参数传入，因此可以完整单测。
library;

import 'package:lexiloop/domain/games/game_constants.dart';
import 'package:lexiloop/domain/games/game_mode.dart';

/// 一局结束后的评级。
///
/// **与旧版的差异**：旧版只有排行榜名次（第 N 名），没有 S/A/B/C 评级。
/// 这里按「得分 / 该模式理论上限」的比例给出评级，让玩家在没进前十时
/// 也能看到自己的相对水平；阈值集中在 `game_constants.dart`。
enum GameRank {
  /// 得分达到理论上限的 [gameRankSPercent]%。
  s('S'),

  /// 得分达到理论上限的 [gameRankAPercent]%。
  a('A'),

  /// 得分达到理论上限的 [gameRankBPercent]%。
  b('B'),

  /// 其余情况。
  c('C');

  const new(this.label);

  /// 展示用字母。
  final String label;
}

/// 一局的作答汇总（结算与评级的输入）。
class GameRoundSummary {
  /// 以各字段构造。
  const new({
    required this.answerScore,
    required this.firstTryCorrect,
    required this.recovered,
    required this.missed,
    required this.mistakeCount,
    required this.maxCombo,
    required this.elapsedMs,
    required this.durationMs,
  });

  /// 逐题得分之和（已含连击、速度与失误罚分）。
  final int answerScore;

  /// 一次答对的题数。
  final int firstTryCorrect;

  /// 失误后纠正完成的题数。
  final int recovered;

  /// 未完成（超时、跳过、堆满）的题数。
  final int missed;

  /// 失误次数（只统计主动点错，与旧版一致）。
  final int mistakeCount;

  /// 最高连击。
  final int maxCombo;

  /// 有效作答耗时之和。
  final int elapsedMs;

  /// 本局时限。
  final int durationMs;

  /// 总题数。
  int get total => firstTryCorrect + recovered + missed;

  /// 首次正确率（百分比）。
  int get accuracy => accuracyPercent(correct: firstTryCorrect, total: total);

  /// 剩余时间（不小于 0）。
  int get remainingMs {
    final left = durationMs - elapsedMs;
    return left < 0 ? 0 : left;
  }
}

/// 单次作答的得分。
///
/// - 答错：扣 [GameScoreRules.mistakePenalty]，连击由调用方清零；
/// - 答对：基础分 + 连击加成 + 速度加减分。
///
/// [comboCount] 是**本次作答之后**的连击数（首次答对传 1），
/// 因此首次答对没有连击加成。
int scoreForAnswer({
  required bool isCorrect,
  required int comboCount,
  required int elapsedMs,
  required GameMode mode,
}) {
  final rules = rulesFor(mode).score;
  if (!isCorrect) return -rules.mistakePenalty;

  final steps = comboSteps(comboCount: comboCount, cap: rules.comboCap);
  final speed = speedBonus(elapsedMs: elapsedMs, rules: rules.speed);
  return rules.basePoints + steps * rules.comboStep + speed;
}

/// 连击加成级数：`comboCount - 1` 且不超过 [cap]、不小于 0。
int comboSteps({required int comboCount, required int cap}) {
  if (comboCount <= 1) return 0;
  final steps = comboCount - 1;
  return steps > cap ? cap : steps;
}

/// 速度加减分。
int speedBonus({required int elapsedMs, required GameSpeedRules rules}) {
  if (elapsedMs <= rules.fastAnswerMs) return rules.fastAnswerBonus;
  if (elapsedMs >= rules.slowAnswerMs) return -rules.slowAnswerPenalty;
  return 0;
}

/// 一局的最终得分：逐题得分之和 + 剩余时间奖励，且不低于 0。
///
/// 失误罚分已在 [scoreForAnswer] 里逐次扣除，此处不再重复。
int finalScore({required GameRoundSummary summary, required GameMode mode}) {
  final rules = rulesFor(mode).timeBonus;
  final bonus = rules.divisorMs <= 0
      ? 0
      : summary.remainingMs ~/ rules.divisorMs;
  final capped = bonus > rules.cap ? rules.cap : bonus;
  final total = summary.answerScore + capped;
  return total < 0 ? 0 : total;
}

/// 正确率（百分比，四舍五入）；总数为 0 时返回 0。
///
/// 与旧版 `Math.round(correct / total * 100)` 一致：
/// 0 题不能除零，全对必须是 100。
int accuracyPercent({required int correct, required int total}) {
  if (total <= 0) return 0;
  final bounded = correct < 0 ? 0 : (correct > total ? total : correct);
  return (bounded * gamePercentScale / total).round();
}

/// 最长连续正确次数；空列表返回 0。
int maxCombo(List<bool> results) {
  var best = 0;
  var current = 0;
  for (final result in results) {
    current = result ? current + 1 : 0;
    if (current > best) best = current;
  }
  return best;
}

/// 该模式的理论最高分：每题都一次答对、连击拉满、全部快答。
///
/// 用于把不同题量的模式放到同一把尺子上评级。
int maxScoreFor(GameMode mode) {
  final rules = rulesFor(mode);
  final perAnswer =
      rules.score.basePoints +
      rules.score.comboCap * rules.score.comboStep +
      rules.score.speed.fastAnswerBonus;
  return rules.session.itemCount * perAnswer + rules.timeBonus.cap;
}

/// 按「得分 / 理论上限」的比例评级。
GameRank rankFor({required int score, required GameMode mode}) {
  final max = maxScoreFor(mode);
  if (max <= 0) return GameRank.c;
  final percent = score * gamePercentScale ~/ max;
  if (percent >= gameRankSPercent) return GameRank.s;
  if (percent >= gameRankAPercent) return GameRank.a;
  if (percent >= gameRankBPercent) return GameRank.b;
  return GameRank.c;
}
