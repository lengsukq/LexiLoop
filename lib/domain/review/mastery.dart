/// 熟练度评分与掌握等级判定。
///
/// 对应旧版 `modules/reviews/mastery.ts`。旧版把权重、归一化分母、罚分与
/// 阈值写成四个对象字面量；这里全部改为 `core/constants.dart` 里的具名常量，
/// 便于单测逐项断言与调参。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';

/// 实时记忆可提取性 R(t)，取值落在 [retrievabilityFloor, retrievabilityCeiling]。
///
/// 基于 FSRS 幂遗忘曲线：
/// - `t = 0`（刚复习完）：R = 1.0
/// - `t = S`（到期日）：R = 0.90
/// - `t` 继续增大：R 平滑衰减，反映真实的记忆可提取程度
double calculateRetrievability(int elapsedDays, double stability) {
  if (stability <= 0 || elapsedDays <= 0) return retrievabilityCeiling;
  final raw = 1 / (1 + (fsrsDecayFactor * elapsedDays) / stability);
  return math.max(retrievabilityFloor, math.min(retrievabilityCeiling, raw));
}

/// 计算 0–100 的熟练分。
///
/// 分项：稳定性 30、正确率 25、间隔 18、连对 10、经验 7、速度 10，
/// 罚分上限 25；最后按可提取性衰减整体缩放。
int calculateMasteryScore(MasteryInput input) {
  if (input.reps == 0) return 0;

  final rawScore =
      _stabilityScore(input.stability) +
      _accuracyScore(input.accuracy) +
      _intervalScore(input.scheduledDays) +
      _streakScore(input.consecutiveCorrect) +
      _experienceScore(input.reps) +
      _speedBonus(input.averageDurationMs) -
      _penalty(input);

  final clamped = rawScore.clamp(0, _masteryMaxScore).toDouble();
  final daysElapsed = input.elapsedDays;
  if (daysElapsed == null || daysElapsed <= 0 || input.stability <= 0) {
    return clamped.round();
  }

  final retrievability = calculateRetrievability(daysElapsed, input.stability);
  final multiplier = math.min(
    retrievabilityCeiling,
    math.max(retentionMultiplierFloor, retrievability / defaultRetentionRate),
  );
  return (clamped * multiplier).round();
}

/// 把熟练分映射为离散等级。
MasteryLevel determineMasteryLevel(MasteryInput input, [int? score]) {
  if (input.reps == 0) return MasteryLevel.newWord;
  final value = score ?? calculateMasteryScore(input);

  if (input.activeWrongWord ||
      input.reps < masteryMinReps ||
      input.scheduledDays < masteryMinScheduledDays ||
      value < masteryLearningScore) {
    return MasteryLevel.learning;
  }
  if (_meets(
    scheduledDays: input.scheduledDays,
    accuracy: input.accuracy,
    recentAgain: input.recentAgain,
    score: value,
    requiredDays: masteryMasteredDays,
    requiredAccuracy: masteryMasteredAccuracy,
    requiredScore: masteryMasteredScore,
  )) {
    return MasteryLevel.mastered;
  }
  if (_meets(
    scheduledDays: input.scheduledDays,
    accuracy: input.accuracy,
    recentAgain: input.recentAgain,
    score: value,
    requiredDays: masteryProficientDays,
    requiredAccuracy: masteryProficientAccuracy,
    requiredScore: masteryProficientScore,
  )) {
    return MasteryLevel.proficient;
  }
  if (input.scheduledDays >= masteryMinScheduledDays &&
      input.accuracy >= masteryFamiliarAccuracy &&
      value >= masteryFamiliarScore) {
    return MasteryLevel.familiar;
  }
  return MasteryLevel.learning;
}

bool _meets({
  required int scheduledDays,
  required double accuracy,
  required int recentAgain,
  required int score,
  required int requiredDays,
  required double requiredAccuracy,
  required int requiredScore,
}) =>
    scheduledDays >= requiredDays &&
    accuracy >= requiredAccuracy &&
    recentAgain == 0 &&
    score >= requiredScore;

/// 稳定性分项：对数缩放，避免早期增长被长间隔淹没。
double _stabilityScore(double stability) => math.min(
  masteryWeightStability.toDouble(),
  math.log(1 + math.max(0, stability)) /
      math.log(1 + masteryStabilityFullDays) *
      masteryWeightStability,
);

double _accuracyScore(double accuracy) =>
    accuracy.clamp(0, 1) * masteryWeightAccuracy.toDouble();

double _intervalScore(int scheduledDays) => math.min(
  masteryWeightInterval.toDouble(),
  math.max(0, scheduledDays) / masteryIntervalFullDays * masteryWeightInterval,
);

double _streakScore(int consecutiveCorrect) => math.min(
  masteryWeightStreak.toDouble(),
  math.max(0, consecutiveCorrect) /
      masteryStreakFullCount *
      masteryWeightStreak,
);

double _experienceScore(int reps) => math.min(
  masteryWeightExperience.toDouble(),
  reps / masteryExperienceFullReps * masteryWeightExperience,
);

double _speedBonus(double? averageDurationMs) {
  if (averageDurationMs == null || averageDurationMs <= 0) return 0;
  final ratio = 1 - averageDurationMs / masterySpeedBaselineMs;
  return math.min(
    masteryWeightSpeed.toDouble(),
    math.max(0, ratio) * masteryWeightSpeed.toDouble(),
  );
}

double _penalty(MasteryInput input) => math.min(
  masteryPenaltyCap.toDouble(),
  (input.lapses * masteryPenaltyPerLapse +
          input.recentAgain * masteryPenaltyPerRecentAgain +
          (input.activeWrongWord ? masteryPenaltyActiveWrongWord : 0))
      .toDouble(),
);

/// 各分项权重之和——熟练分的理论上限。
const int _masteryMaxScore =
    masteryWeightStability +
    masteryWeightAccuracy +
    masteryWeightInterval +
    masteryWeightStreak +
    masteryWeightExperience +
    masteryWeightSpeed;
