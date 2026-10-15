/// 错词状态的转移规则。
///
/// 对应旧版 `modules/reviews/wrong-state.ts` 的判定部分（SQL 写入在 DAO 层）。
///
/// **设计要点**：`consecutive_correct` 记的是**连续正确的自然日数**，
/// 不是连续正确次数。否则同一天刷十遍就能把错词「洗白」，
/// 而这恰恰是间隔重复要防的假象。因此这里必须走
/// [localDayOrdinal] 而不是 `dayMs` 相减。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';

/// 错词状态的下一版本。
class WrongStateTransition {
  /// 以各字段构造。
  const new({
    required this.active,
    required this.wrongCount,
    required this.hardCount,
    required this.consecutiveCorrect,
    required this.lastWrongAt,
    required this.lastCorrectAt,
    required this.resolvedAt,
  });

  /// 是否仍处于活跃错词状态。
  final bool active;

  /// 累计答错次数。
  final int wrongCount;

  /// 累计「模糊」次数。
  final int hardCount;

  /// 连续正确的自然日数。
  final int consecutiveCorrect;

  /// 上次答错时间（epoch 毫秒）。
  final int? lastWrongAt;

  /// 上次答对时间（epoch 毫秒）。
  final int? lastCorrectAt;

  /// 解除时间；未解除时为 `null`。
  final int? resolvedAt;
}

/// 计算错词状态的转移。
///
/// 返回 `null` 表示**无需落库**：该词条此前从未答错或答模糊，
/// 而本次又答对了。旧版在这种情况下同样不写行，避免为「从没错过的词」
/// 生成一行噪声数据。
///
/// 各分支与旧版逐条对齐：
/// - 评为「简单」：直接解除（用户显式表示「太简单了」）；
/// - 答错或评为「重来」：记为一次错，连续正确清零；
/// - 评为「模糊」：记为一次模糊，连续正确清零，但不增加错误次数
///   ——「记得但不确定」与「完全忘了」是两回事；
/// - 评为「记得」：按自然日累加连续正确天数，满足条件即解除。
WrongStateTransition? transitionWrongState({
  required WrongStateSnapshot? current,
  required ReviewRating rating,
  required bool isCorrect,
  required int now,
}) {
  if (rating == ReviewRating.easy) {
    if (current == null) return null;
    return WrongStateTransition(
      active: false,
      wrongCount: current.wrongCount,
      hardCount: current.hardCount,
      consecutiveCorrect: 1,
      lastWrongAt: current.lastWrongAt,
      lastCorrectAt: now,
      resolvedAt: now,
    );
  }

  if (!isCorrect || rating == ReviewRating.again) {
    return WrongStateTransition(
      active: true,
      wrongCount: (current?.wrongCount ?? 0) + 1,
      hardCount: current?.hardCount ?? 0,
      consecutiveCorrect: 0,
      lastWrongAt: now,
      lastCorrectAt: current?.lastCorrectAt,
      resolvedAt: null,
    );
  }

  if (rating == ReviewRating.hard) {
    return WrongStateTransition(
      active: true,
      wrongCount: current?.wrongCount ?? 0,
      hardCount: (current?.hardCount ?? 0) + 1,
      consecutiveCorrect: 0,
      lastWrongAt: current?.lastWrongAt,
      lastCorrectAt: current?.lastCorrectAt,
      resolvedAt: null,
    );
  }

  if (current == null) return null;

  final consecutiveCorrect = _nextConsecutiveCorrect(current, now);
  final resolved =
      consecutiveCorrect >= wrongWordResolveConsecutiveDays &&
      _wrongIsOldEnough(current, now);
  return WrongStateTransition(
    active: !resolved && current.active,
    wrongCount: current.wrongCount,
    hardCount: current.hardCount,
    consecutiveCorrect: consecutiveCorrect,
    lastWrongAt: current.lastWrongAt,
    lastCorrectAt: now,
    resolvedAt: resolved ? now : null,
  );
}

/// 把转移结果压缩为熟练度计算需要的两个字段。
///
/// 转移为 `null`（无需落库）等价于「不在错词本里、连续正确 1 天」。
WrongStateResult wrongStateResultOf(WrongStateTransition? transition) =>
    transition == null
    ? const WrongStateResult(active: false, consecutiveCorrect: 1)
    : WrongStateResult(
        active: transition.active,
        consecutiveCorrect: transition.consecutiveCorrect,
      );

/// 连续正确天数：同一天内重复答对不累加。
int _nextConsecutiveCorrect(WrongStateSnapshot current, int now) {
  final lastCorrectAt = current.lastCorrectAt;
  if (lastCorrectAt == null) return 1;

  final dayGap = localDayOrdinal(now) - localDayOrdinal(lastCorrectAt);
  if (dayGap == 0) return current.consecutiveCorrect;
  if (dayGap == 1) return current.consecutiveCorrect + 1;
  return 1;
}

/// 距上次答错是否已够久。
///
/// 与连续正确天数共同作用：没有这一条，一天之内连续答对三次
/// 就能解除错词。
bool _wrongIsOldEnough(WrongStateSnapshot current, int now) {
  final lastWrongAt = current.lastWrongAt;
  if (lastWrongAt == null) return true;
  return localDayOrdinal(now) - localDayOrdinal(lastWrongAt) >=
      wrongWordResolveMinDayGap;
}
