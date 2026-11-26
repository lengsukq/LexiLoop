/// 从作答流水重放一个词的学习状态。
///
/// **为什么需要重放**：合并两台设备的进度时，卡片、错词状态、熟练度都是
/// `review_logs` 的**函数**。两边各推进了一部分历史，正确的结果是把两份流水
/// 并起来、按时间顺序重新走一遍，而不是挑"哪一边更新"——后者会拼出
/// 「卡片来自 A、错词状态来自 B」这类自相矛盾的状态。
///
/// **为什么必须是纯函数**：`test/services/merge/learning_replay_test.dart`
/// 拿它和真实的复习流水线（`ReviewService.processAnswer`）逐字段对比。
/// 只要它碰数据库，那条对比就得先构造一整套环境，也就没人会去写。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/review/mastery.dart';
import 'package:lexiloop/domain/review/wrong_state.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';

/// 重放所需的单条作答。
///
/// 只带四个字段：卡片要看**何时、评了几级**，错词还要看**这一题答对了没有**，
/// 熟练度还要看**耗时**。日志里的题干、用户答案、卡片快照都与重放无关。
class ReplayLog {
  /// 以各字段构造。
  const new({
    required this.reviewedAt,
    required this.rating,
    required this.isCorrect,
    this.durationMs,
  });

  /// 作答时间（epoch 毫秒）。
  final int reviewedAt;

  /// 用户（或判题降级后）给出的评级。
  final ReviewRating rating;

  /// 这一题是否答对。
  final bool isCorrect;

  /// 有效作答耗时（毫秒）；缺失或非正表示没有样本。
  final int? durationMs;
}

/// 从一行 `review_logs`（数据库或备份 JSON）构造一条重放日志。
///
/// 两种来源的类型不同：SQLite 的布尔是 `0`/`1`，JSON 里可能是 `true`/`false`。
/// 枚举按 wire 字符串解析；解析不出来只可能说明这行数据本身坏了，
/// 因此**明确报错**而不是猜一个默认值——猜出来的评级会一路污染卡片。
ReplayLog replayLogFromRow(Map<String, Object?> row) => ReplayLog(
  reviewedAt: _intOf(row['reviewed_at']) ?? 0,
  rating: _ratingOf(row['rating']),
  isCorrect: _boolOf(row['is_correct']),
  durationMs: _intOf(row['duration_ms']),
);

/// 一个词的流水统计（与 `word_review_stats` 的口径一致）。
class WordStatTotals {
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

  /// 近 30 天的「重来」次数。
  final int recentAgain;

  /// 平均有效耗时（毫秒）；无样本时为 `null`。
  final double? averageDurationMs;

  /// 历史正确率；无样本时为 0。
  ///
  /// 与 `ReviewStatistics.accuracy` 同一口径——熟练度用的是那个值。
  double get accuracy => total == 0 ? 0 : correct / total;
}

/// 重放得到的完整学习状态。
class ReplayedLearningState {
  /// 以各字段构造。
  const new({
    required this.card,
    required this.wrong,
    required this.stats,
    required this.masteryScore,
    required this.masteryLevel,
  });

  /// 重放后的卡片状态。
  final ReviewCardState card;

  /// 重放后的错词状态；`null` 表示这条流水从未产生过错词记录，
  /// 因此库里不该有 `wrong_word_states` 行。
  final WrongStateTransition? wrong;

  /// 流水统计。
  final WordStatTotals stats;

  /// 熟练分（0–100）。
  final int masteryScore;

  /// 掌握等级。
  final MasteryLevel masteryLevel;
}

/// 按 `[logs]` 的顺序重放，得到该词的学习状态。
///
/// **[logs] 必须已按 `(reviewed_at, client_answer_id)` 升序排好**：
/// 排序是合并逻辑的一部分（两台设备的流水要按时间交织），放在这里会让
/// 这个函数多认识一个与重放无关的字段。
///
/// [now] 决定 14/30 天窗口的起点。生产路径传「合并发生的时间」，
/// 与流水线传「这次作答的时间」语义一致：都是「以现在为基准回看」。
ReplayedLearningState replayWordHistory({
  required List<ReplayLog> logs,
  required FsrsScheduler scheduler,
  required int now,
}) {
  if (logs.isEmpty) {
    throw const ValidationError(
      AppErrorCode.backupInvalidFormat,
      details: '重放需要至少一条作答日志',
    );
  }

  var card = scheduler.emptyCard(logs.first.reviewedAt);
  WrongStateTransition? wrong;
  for (final log in logs) {
    card = scheduler.schedule(
      card: card,
      nowMs: log.reviewedAt,
      rating: log.rating,
    );
    final next = transitionWrongState(
      current: wrong == null ? null : _snapshotOf(wrong),
      rating: log.rating,
      isCorrect: log.isCorrect,
      now: log.reviewedAt,
    );
    if (next != null) wrong = next;
  }

  final stats = wordStatTotalsFrom(logs, now: now);
  final input = MasteryInput(
    stability: card.stability,
    scheduledDays: card.scheduledDays,
    reps: card.reps,
    lapses: card.lapses,
    accuracy: stats.accuracy,
    // 与流水线的 `wrongStateResultOf` 同一套兜底：没有错词记录时按
    // 「不在错词本里、连续正确 1 天」计。
    consecutiveCorrect: wrong?.consecutiveCorrect ?? 1,
    activeWrongWord: wrong?.active ?? false,
    recentAgain: stats.recentAgain,
    averageDurationMs: stats.averageDurationMs,
  );
  final score = calculateMasteryScore(input);
  return ReplayedLearningState(
    card: card,
    wrong: wrong,
    stats: stats,
    masteryScore: score,
    masteryLevel: determineMasteryLevel(input, score),
  );
}

/// 按 `word_review_stats` 的口径统计一批流水。
///
/// **口径与 SQL 逐条对齐**（`test/services/merge/word_stats_test.dart` 拿它和
/// 导入器的 SQL 对拍）：只有 `duration_ms > 0` 的样本计入平均耗时；
/// 30 天窗口用 [masteryWindowMs]，与 `_recomputeStatWindows` 一致。
WordStatTotals wordStatTotalsFrom(
  Iterable<ReplayLog> logs, {
  required int now,
}) {
  var total = 0;
  var correct = 0;
  var recentAgain = 0;
  var durationTotal = 0;
  var durationCount = 0;
  final since = now - masteryWindowMs;

  for (final log in logs) {
    total += 1;
    if (log.isCorrect) correct += 1;
    if (log.rating == ReviewRating.again && log.reviewedAt >= since) {
      recentAgain += 1;
    }
    final duration = log.durationMs;
    if (duration != null && duration > 0) {
      durationTotal += duration;
      durationCount += 1;
    }
  }

  return WordStatTotals(
    total: total,
    correct: correct,
    recentAgain: recentAgain,
    averageDurationMs: durationCount > 0 ? durationTotal / durationCount : null,
  );
}

/// 把转移结果压成下一次转移需要的前状态。
///
/// 两个类型的字段一一对应（`resolvedAt` 不参与判定，转移结果里才有）。
WrongStateSnapshot _snapshotOf(WrongStateTransition transition) =>
    WrongStateSnapshot(
      active: transition.active,
      wrongCount: transition.wrongCount,
      hardCount: transition.hardCount,
      consecutiveCorrect: transition.consecutiveCorrect,
      lastWrongAt: transition.lastWrongAt,
      lastCorrectAt: transition.lastCorrectAt,
    );

/// 解析评级；未知取值直接报错。
ReviewRating _ratingOf(Object? value) {
  if (value is String) {
    final rating = wireLookup(ReviewRating.values, value);
    if (rating != null) return rating;
  }
  throw ValidationError(
    AppErrorCode.backupInvalidFormat,
    details: 'review_logs.rating 含未知取值：$value',
  );
}

/// 宽容地读一个布尔：`true`/`1` 为真。
bool _boolOf(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return false;
}

/// 宽容地读一个整数。
int? _intOf(Object? value) {
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}
