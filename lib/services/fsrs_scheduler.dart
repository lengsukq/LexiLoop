/// FSRS 间隔重复调度适配层。
///
/// 为什么单独一层：`package:fsrs` 的 [Card] 是**可变**对象，字段也与旧版
/// ts-fsrs 不一致——Dart 版没有 `New` 状态，也没有
/// `reps`/`lapses`/`elapsed_days`/`scheduled_days`。上层只认识不可变的
/// [ReviewCardState]，两边在这里转换，第三方类型因此不会泄漏到其他层。
library;

import 'dart:math' as math;

import 'package:fsrs/fsrs.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';

/// `Card.cardId` 的占位值。
///
/// fsrs 只把它写进 `ReviewLog`，而本层不消费日志；[ReviewCardState] 也不含
/// 词条 ID（卡片与词条由 `review_cards.word_id` 关联）。
const int _placeholderCardId = 0;

/// 预览的固定输出顺序：AGAIN、HARD、GOOD、EASY。
///
/// 显式列出而不依赖枚举声明顺序，避免将来调整枚举时静默改变界面上的按钮顺序。
const List<ReviewRating> _previewRatings = <ReviewRating>[
  ReviewRating.again,
  ReviewRating.hard,
  ReviewRating.good,
  ReviewRating.easy,
];

/// 把目标保持率夹到合法区间。
///
/// 越界值会把间隔算成 0 或天文数字，而设置页允许用户自由输入。
double _clampRetention(double value) =>
    value.clamp(minRetentionRate, maxRetentionRate);

/// epoch 毫秒 → UTC 时间。
///
/// fsrs 的 `reviewCard` 显式拒绝非 UTC 时间，统一在这里转换，避免每个调用点
/// 各写一遍 `isUtc: true`。
DateTime _toUtc(int epochMs) =>
    DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true);

/// 两个时间戳之间的整天数；倒挂（时钟回拨）按 0 计。
int _wholeDaysBetween(int fromMs, int toMs) =>
    math.max(0, (toMs - fromMs) ~/ dayMs);

/// 一次复习后四个等级各自的排期预览。
class FsrsIntervalPreview {
  /// 以各字段构造。
  const new({
    required this.rating,
    required this.nextDueAt,
    required this.scheduledDays,
  });

  /// 产生这条预览的评级。
  final ReviewRating rating;

  /// 按该评级作答后的到期时间（epoch 毫秒）。
  final int nextDueAt;

  /// 按该评级作答后排定的间隔天数（不足一天为 0）。
  final int scheduledDays;
}

/// FSRS 调度器。
///
/// 一个实例绑定一个目标保持率：`package:fsrs` 的 [Scheduler] 把
/// `desiredRetention` 固化在内部。旧版为此维护了一个按保持率索引的全局缓存
/// Map（无上限，见 `docs/CLEAN_CODE_BASELINE.md`）；本版改由调用方持有实例，
/// 生命周期明确，也没有全局可变状态。
class FsrsScheduler {
  /// 以目标记忆保持率构造。
  ///
  /// [requestRetention] 会夹到 [minRetentionRate] 与 [maxRetentionRate] 之间。
  ///
  /// **刻意关闭 fuzz**（旧版是 `enable_fuzz: true`）：Dart 版的 fuzz 用未播种
  /// 的 `Random`，同一张卡、同一时刻两次 [preview] 会给出不同结果，HARD 甚至
  /// 可能晚于 GOOD——而预览的契约是「单调不减」的确定预测。关掉之后
  /// [preview] 与 [schedule] 的结果逐字段一致。
  ///
  /// 学习步长沿用包内默认值（1 分钟 / 10 分钟，重学 10 分钟），与旧版
  /// ts-fsrs v5 的默认值相同。
  new({double requestRetention = defaultRetentionRate})
    : _scheduler = Scheduler(
        desiredRetention: _clampRetention(requestRetention),
        maximumInterval: fsrsMaximumIntervalDays,
        enableFuzzing: false,
      );

  final Scheduler _scheduler;

  /// 从未复习过的空白卡片。
  ///
  /// 对应 ts-fsrs 的 `createEmptyCard(now)`：New 态、稳定性与难度为 0、
  /// 没有上次复习时间。
  ReviewCardState emptyCard(int nowMs) => ReviewCardState(
    dueAt: nowMs,
    stability: 0,
    difficulty: 0,
    elapsedDays: 0,
    scheduledDays: 0,
    reps: 0,
    lapses: 0,
    fsrsState: fsrsStateNew,
    learningSteps: 0,
    lastReviewAt: null,
  );

  /// 按评级推进卡片，返回新状态（不修改入参）。
  ReviewCardState schedule({
    required ReviewCardState card,
    required int nowMs,
    required ReviewRating rating,
  }) {
    final reviewed = _scheduler.reviewCard(
      toFsrsCard(card),
      _toFsrsRating(rating),
      reviewDateTime: _toUtc(nowMs),
    );
    return fromFsrsCard(
      reviewed.card,
      previous: card,
      rating: rating,
      nowMs: nowMs,
    );
  }

  /// 预览四个等级各自的排期，顺序固定为 AGAIN、HARD、GOOD、EASY。
  ///
  /// 直接复用 [schedule]，保证「预览」与「真按下去」的结果完全一致。
  List<FsrsIntervalPreview> preview({
    required ReviewCardState card,
    required int nowMs,
  }) {
    final previews = <FsrsIntervalPreview>[];
    for (final rating in _previewRatings) {
      final next = schedule(card: card, nowMs: nowMs, rating: rating);
      previews.add(
        FsrsIntervalPreview(
          rating: rating,
          nextDueAt: next.dueAt,
          scheduledDays: next.scheduledDays,
        ),
      );
    }
    return previews;
  }

  /// 把纯数据卡片转换为 `package:fsrs` 的 [Card]。
  ///
  /// 三个必须留意的差异：
  /// 1. [Card] 可变，fsrs 会就地改写它，所以每次转换都新建对象，绝不共享；
  /// 2. `reviewCard` 要求时间参数是 UTC，时间戳统一按 UTC 还原；
  /// 3. [Card] 不保存 `reps`/`lapses`/`elapsed_days`/`scheduled_days`，
  ///    这些字段由本层自己累计与推导（见 [fromFsrsCard]）。
  Card toFsrsCard(ReviewCardState card) {
    // 没有初始稳定性/难度的卡片必须走「初始值」分支：fsrs 对 0 求负幂会得到
    // Infinity，转 int 时直接抛异常；而「从未复习」正是 New 态的定义。
    if (!_hasInitialValues(card)) {
      // `Card` 的默认状态就是 learning，故此处不显式传 state。
      return Card(cardId: _placeholderCardId, step: 0, due: _toUtc(card.dueAt));
    }
    return Card(
      cardId: _placeholderCardId,
      state: _toFsrsState(card.fsrsState),
      step: card.learningSteps,
      stability: card.stability,
      difficulty: card.difficulty,
      due: _toUtc(card.dueAt),
      lastReview: card.lastReviewAt == null ? null : _toUtc(card.lastReviewAt!),
    );
  }

  /// 用 fsrs 的调度结果更新纯数据卡片。
  ///
  /// [previous] 与 [rating] 是 fsrs 侧不存在的信息：Dart 版 [Card] 没有
  /// `reps`/`lapses`，也没有旧版的 `elapsed_days`/`scheduled_days`，只能由
  /// 调用方补齐。[nowMs] 用来推导本次的已过天数与排定的间隔天数。
  ReviewCardState fromFsrsCard(
    Card card, {
    required ReviewCardState previous,
    required ReviewRating rating,
    required int nowMs,
  }) {
    final dueAt = card.due.millisecondsSinceEpoch;
    return ReviewCardState(
      dueAt: dueAt,
      stability: card.stability ?? previous.stability,
      difficulty: card.difficulty ?? previous.difficulty,
      elapsedDays: _wholeDaysBetween(previous.lastReviewAt ?? nowMs, nowMs),
      scheduledDays: _wholeDaysBetween(nowMs, dueAt),
      reps: previous.reps + 1,
      lapses:
          previous.lapses +
          (_isLapse(previous: previous, rating: rating) ? 1 : 0),
      fsrsState: _fsrsStateOf(card),
      learningSteps: card.step ?? 0,
      lastReviewAt: card.lastReview?.millisecondsSinceEpoch,
    );
  }

  /// 卡片是否已拿到 fsrs 算出的初始稳定性与难度。
  ///
  /// `review_cards` 的这两列是 NOT NULL，坏数据会以 0 出现；只要缺一项就按新卡
  /// 处理，宁可重学一轮，也不要让调度崩在 `Infinity.toInt()` 上。
  bool _hasInitialValues(ReviewCardState card) =>
      card.lastReviewAt != null && card.stability > 0 && card.difficulty > 0;

  /// 本次是否算一次「遗忘」。
  ///
  /// 与 ts-fsrs 一致：只有复习态的卡片再次评为 AGAIN 才算遗忘；学习态/重学态
  /// 答错只是退回更早的学习步，不是新的遗忘。
  bool _isLapse({
    required ReviewCardState previous,
    required ReviewRating rating,
  }) =>
      rating == ReviewRating.again && previous.fsrsState == State.review.value;

  /// 把 0–3 的状态序号映射到 fsrs 的 [State]。
  ///
  /// 0（New）与 1（learning）在 Dart 版共用 [State.learning]，两者的区别由
  /// 「有没有上次复习时间」表达（见 [toFsrsCard]）；未知值同样退化为 learning，
  /// 避免坏数据直接把整个复习流程打断。
  State _toFsrsState(int fsrsState) {
    if (fsrsState == State.review.value) return State.review;
    if (fsrsState == State.relearning.value) return State.relearning;
    return State.learning;
  }

  /// 把 fsrs 的 [State] 映射回 0–3 的状态序号。
  ///
  /// [State] 没有 New，因此用「learning 且从未复习」还原成 0，
  /// 否则往返转换会把新卡记成学习中的卡。
  int _fsrsStateOf(Card card) =>
      card.state == State.learning && card.lastReview == null
      ? fsrsStateNew
      : card.state.value;

  /// 评级映射。
  ///
  /// 用穷举 switch 而不是按下标取值：枚举改名或调整顺序时编译器会直接报错。
  Rating _toFsrsRating(ReviewRating rating) => switch (rating) {
    ReviewRating.again => Rating.again,
    ReviewRating.hard => Rating.hard,
    ReviewRating.good => Rating.good,
    ReviewRating.easy => Rating.easy,
  };
}
