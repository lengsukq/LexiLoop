/// 复习（作答）相关的纯数据模型。
///
/// 这些类型是 domain 层与 data 层之间的契约：DAO 从行映射出来，
/// 纯函数在其上计算，service 再写回。**不含任何行为**，便于构造测试数据。
library;

import 'package:lexiloop/domain/enums.dart';

/// 复习上下文中「词条」侧的最小视图。
class ReviewWord {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    required this.initializationStatus,
    required this.isSuspended,
    required this.definitionsJson,
  });

  /// 词条 ID。
  final int id;

  /// 展示用文本。
  final String term;

  /// 归一化文本（判题比对基准）。
  final String normalizedTerm;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 内容类型（单词 / 短语 / 句子）。
  final LexicalContentType contentType;

  /// 初始化状态。
  final InitializationStatus initializationStatus;

  /// 是否已暂停学习。
  final bool isSuspended;

  /// 释义 JSON 原文。
  final String? definitionsJson;

  /// 是否处于可复习状态（已就绪或部分就绪，且未暂停）。
  bool get isReviewable =>
      !isSuspended &&
      (initializationStatus == InitializationStatus.ready ||
          initializationStatus == InitializationStatus.partial);
}

/// FSRS 卡片状态（与 `review_cards` 一行对应）。
class ReviewCardState {
  /// 以各字段构造。
  const new({
    required this.dueAt,
    required this.stability,
    required this.difficulty,
    required this.elapsedDays,
    required this.scheduledDays,
    required this.reps,
    required this.lapses,
    required this.fsrsState,
    required this.learningSteps,
    required this.lastReviewAt,
  });

  /// 下次到期时间（epoch 毫秒）。
  final int dueAt;

  /// FSRS 记忆稳定性。
  final double stability;

  /// FSRS 难度。
  final double difficulty;

  /// 距上次复习经过的天数。
  final int elapsedDays;

  /// 当前排定的间隔天数。
  final int scheduledDays;

  /// 累计复习次数。
  final int reps;

  /// 累计遗忘次数。
  final int lapses;

  /// FSRS 内部状态序号（0–3）。
  final int fsrsState;

  /// 学习阶段的步进位置。
  final int learningSteps;

  /// 上次复习时间（epoch 毫秒）。
  final int? lastReviewAt;

  /// 序列化为复习日志里的卡片快照 JSON。
  ///
  /// 手写而非 `jsonEncode`：字段名必须与旧版 `ts-fsrs` 的 `Card` 一致
  /// （`elapsed_days`、`last_review` 等），备份回放时才可比对。
  String toJson() =>
      '{"due":$dueAt,"stability":$stability,"difficulty":$difficulty,'
      '"elapsed_days":$elapsedDays,"scheduled_days":$scheduledDays,'
      '"reps":$reps,"lapses":$lapses,"state":$fsrsState,'
      '"learning_steps":$learningSteps,'
      '"last_review":${lastReviewAt ?? 'null'}}';
}

/// 错词状态快照（与 `wrong_word_states` 一行对应）。
class WrongStateSnapshot {
  /// 以各字段构造。
  const new({
    required this.active,
    required this.wrongCount,
    required this.hardCount,
    required this.consecutiveCorrect,
    required this.lastWrongAt,
    required this.lastCorrectAt,
  });

  /// 是否处于活跃错词状态。
  final bool active;

  /// 累计答错次数。
  final int wrongCount;

  /// 累计「模糊」次数。
  final int hardCount;

  /// 连续正确的**自然日**数。
  final int consecutiveCorrect;

  /// 上次答错时间（epoch 毫秒）。
  final int? lastWrongAt;

  /// 上次答对时间（epoch 毫秒）。
  final int? lastCorrectAt;
}

/// 错词状态的更新结果。
class WrongStateResult {
  /// 以各字段构造。
  const new({required this.active, required this.consecutiveCorrect});

  /// 更新后是否仍处于活跃错词状态。
  final bool active;

  /// 更新后的连续正确天数。
  final int consecutiveCorrect;
}

/// 词条的累计作答统计（与 `word_review_stats` 一行对应）。
class ReviewStatistics {
  /// 以各字段构造。
  const new({
    required this.total,
    required this.correct,
    required this.recentAgain,
    required this.averageDurationMs,
  });

  /// 累计作答次数。
  final int total;

  /// 累计答对次数。
  final int correct;

  /// 近 30 天 AGAIN 次数。
  final int recentAgain;

  /// 平均作答耗时（毫秒）；无有效样本时为 `null`。
  final double? averageDurationMs;

  /// 历史正确率；无样本时为 0。
  double get accuracy => total == 0 ? 0 : correct / total;
}

/// 一次作答的输入。
class AnswerInput {
  /// 以各字段构造。
  const new({
    required this.clientAnswerId,
    required this.wordId,
    required this.rating,
    required this.questionType,
    this.studySessionId,
    this.studySessionItemId,
    this.userAnswer,
    this.durationMs,
  });

  /// 客户端生成的幂等键。
  ///
  /// 无服务端后这条比旧版更重要：重复提交（重放、误触）必须被吸收，
  /// 否则同一题会二次推进 FSRS。
  final String clientAnswerId;

  /// 词条 ID。
  final int wordId;

  /// 用户自评等级。
  final ReviewRating rating;

  /// 题型。
  final QuestionType questionType;

  /// 所属学习会话 ID（会话内作答时必填）。
  final int? studySessionId;

  /// 所属会话题目 ID（会话内作答时必填）。
  final int? studySessionItemId;

  /// 用户作答原文（拼写题、选择题）。
  final String? userAnswer;

  /// 作答耗时（毫秒）。
  final int? durationMs;

  /// 是否带有完整的学习会话上下文。
  bool get hasSessionContext =>
      studySessionId != null && studySessionItemId != null;
}

/// 判题结果。
class AnswerEvaluation {
  /// 以各字段构造。
  const new({
    required this.isCorrect,
    required this.effectiveRating,
    required this.expectedAnswer,
    required this.presentedPrompt,
  });

  /// 客观判定的正误。
  final bool isCorrect;

  /// 实际用于 FSRS 调度的等级。
  ///
  /// 客观题答错时会被降级为 AGAIN，除非用户显式选了「模糊」或「简单」——
  /// 那两种情况分别表示「不算全忘」与「其实会，只是选错」。
  final ReviewRating effectiveRating;

  /// 期望答案（用于复盘展示）。
  final String expectedAnswer;

  /// 题干（用于复盘展示）。
  final String presentedPrompt;
}

/// 熟练度计算的输入。
class MasteryInput {
  /// 以各字段构造。
  const new({
    required this.stability,
    required this.scheduledDays,
    required this.reps,
    required this.lapses,
    required this.accuracy,
    required this.consecutiveCorrect,
    required this.activeWrongWord,
    required this.recentAgain,
    this.averageDurationMs,
    this.elapsedDays,
  });

  /// FSRS 记忆稳定性。
  final double stability;

  /// 当前排定的间隔天数。
  final int scheduledDays;

  /// 累计复习次数。
  final int reps;

  /// 累计遗忘次数。
  final int lapses;

  /// 历史正确率（0–1）。
  final double accuracy;

  /// 连续正确天数。
  final int consecutiveCorrect;

  /// 是否处于活跃错词状态。
  final bool activeWrongWord;

  /// 近 30 天 AGAIN 次数。
  final int recentAgain;

  /// 平均作答耗时（毫秒）。
  final double? averageDurationMs;

  /// 距上次复习经过的天数。
  final int? elapsedDays;
}

/// 一次作答的完整结果。
class ReviewOutcome {
  /// 以各字段构造。
  const new({
    required this.reviewLogId,
    required this.isCorrect,
    required this.rating,
    required this.expectedAnswer,
    required this.scheduledDays,
    required this.masteryScore,
    required this.masteryLevel,
    required this.wrongWordActive,
    required this.idempotent,
    this.nextDueAt,
    this.adaptiveFollowUp,
  });

  /// 复习日志 ID。
  final int reviewLogId;

  /// 客观判定的正误。
  final bool isCorrect;

  /// 实际生效的等级。
  final ReviewRating rating;

  /// 期望答案。
  final String expectedAnswer;

  /// 下次到期时间（epoch 毫秒）。
  final int? nextDueAt;

  /// 下次间隔天数。
  final int scheduledDays;

  /// 更新后的熟练分。
  final int masteryScore;

  /// 更新后的掌握等级。
  final MasteryLevel masteryLevel;

  /// 更新后是否仍处于活跃错词状态。
  final bool wrongWordActive;

  /// 本次请求是否命中了幂等键（未产生新日志）。
  final bool idempotent;

  /// 本次答错触发的会话内追问题；未触发时为 `null`。
  final AdaptiveFollowUp? adaptiveFollowUp;
}

/// 会话内追问题。
class AdaptiveFollowUp {
  /// 以各字段构造。
  const new({
    required this.questionType,
    required this.position,
    required this.repetition,
  });

  /// 追问题型。
  final QuestionType questionType;

  /// 插入位置。
  final double position;

  /// 这是该词条的第几次追问（0 起）。
  final int repetition;
}
