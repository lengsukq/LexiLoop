/// FSRS 调度适配层测试。
///
/// 重点不是「fsrs 算得对不对」（那是上游库的事），而是适配层的四条契约：
/// 1. 0–3 的 `fsrs_state` 与「缺 New 值」的 Dart 版 `State` 枚举能无损往返；
/// 2. 预览必须四个等级齐全、顺序固定、到期时间单调不减；
/// 3. 越界的保持率被夹取而不是抛出；
/// 4. 坏数据（稳定性/难度为 0）不会把复习流程打断。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';

void main() {
  // 固定基准时刻：测试不依赖真实时钟，也不受时区影响。
  final now = DateTime.utc(2025, 1, 1, 12).millisecondsSinceEpoch;

  // 构造一张「已复习过若干次」的复习态卡片。
  ReviewCardState reviewStateCard({
    int scheduledDays = 30,
    int reps = 3,
    int elapsedDays = 0,
  }) {
    final lastReviewAt = now - elapsedDays * dayMs;
    return ReviewCardState(
      dueAt: lastReviewAt + scheduledDays * dayMs,
      stability: 16.15,
      difficulty: 5,
      elapsedDays: elapsedDays,
      scheduledDays: scheduledDays,
      reps: reps,
      lapses: 0,
      fsrsState: fsrs.State.review.value,
      learningSteps: 0,
      lastReviewAt: lastReviewAt,
    );
  }

  // 构造一张「学习步进中」的卡片：已完成第 1 步，下一步是 10 分钟。
  ReviewCardState learningStateCard() => ReviewCardState(
    dueAt: now + 10 * minuteMs,
    stability: 3.2602,
    difficulty: 4.88,
    elapsedDays: 0,
    scheduledDays: 0,
    reps: 1,
    lapses: 0,
    fsrsState: fsrs.State.learning.value,
    learningSteps: 1,
    lastReviewAt: now,
  );

  group('emptyCard', () {
    test('空白卡片是 New 态，计数与稳定性全为 0', () {
      final card = FsrsScheduler().emptyCard(now);

      expect(card.reps, 0);
      expect(card.lapses, 0);
      // Dart 版 State 枚举没有 New，约定用 0 表示（见实现里的私有常量）。
      expect(card.fsrsState, 0);
      expect(card.learningSteps, 0);
      expect(card.stability, 0);
      expect(card.difficulty, 0);
      expect(card.dueAt, now);
      expect(card.lastReviewAt, isNull);
    });
  });

  group('schedule', () {
    test('首次 GOOD：reps 加一，到期时间往后推', () {
      final scheduler = FsrsScheduler();
      final empty = scheduler.emptyCard(now);

      final next = scheduler.schedule(
        card: empty,
        nowMs: now,
        rating: ReviewRating.good,
      );

      expect(next.reps, 1);
      expect(next.lapses, 0);
      expect(next.dueAt, greaterThan(now));
      expect(next.lastReviewAt, now);
      // 新卡 GOOD 只推进到第二个学习步（10 分钟），还没进入复习态。
      expect(next.fsrsState, fsrs.State.learning.value);
      expect(next.learningSteps, 1);
      expect(next.scheduledDays, 0);
    });

    test('AGAIN 的到期时间明显早于 EASY', () {
      final scheduler = FsrsScheduler();
      final empty = scheduler.emptyCard(now);

      final again = scheduler.schedule(
        card: empty,
        nowMs: now,
        rating: ReviewRating.again,
      );
      final easy = scheduler.schedule(
        card: empty,
        nowMs: now,
        rating: ReviewRating.easy,
      );

      expect(again.dueAt, lessThan(easy.dueAt));
      // AGAIN 退回第一个学习步（分钟级），EASY 直接进复习态（天级）。
      expect(easy.dueAt - again.dueAt, greaterThanOrEqualTo(dayMs));
      expect(again.fsrsState, fsrs.State.learning.value);
      expect(easy.fsrsState, fsrs.State.review.value);
    });

    test('复习态再次 AGAIN 计入遗忘，学习态答错不计', () {
      final scheduler = FsrsScheduler();

      final reviewAgain = scheduler.schedule(
        card: reviewStateCard(),
        nowMs: now,
        rating: ReviewRating.again,
      );
      final reviewGood = scheduler.schedule(
        card: reviewStateCard(),
        nowMs: now,
        rating: ReviewRating.good,
      );
      final learningAgain = scheduler.schedule(
        card: learningStateCard(),
        nowMs: now,
        rating: ReviewRating.again,
      );

      expect(reviewAgain.lapses, 1);
      expect(reviewAgain.fsrsState, fsrs.State.relearning.value);
      expect(reviewGood.lapses, 0);
      expect(learningAgain.lapses, 0);
    });

    test('不修改传入的卡片', () {
      final scheduler = FsrsScheduler();
      final before = reviewStateCard();
      final snapshot = before.toJson();

      final next = scheduler.schedule(
        card: before,
        nowMs: now,
        rating: ReviewRating.good,
      );

      expect(before.toJson(), snapshot);
      expect(identical(next, before), isFalse);
    });

    test('每次转换都新建 fsrs 卡片，不共享可变状态', () {
      final scheduler = FsrsScheduler();
      final card = reviewStateCard();

      final first = scheduler.toFsrsCard(card);
      final second = scheduler.toFsrsCard(card);
      // fsrs 的 Card 是可变对象：改一张不能影响另一张。
      first.stability = 1;

      expect(identical(first, second), isFalse);
      expect(second.stability, card.stability);
    });

    test('稳定性/难度为 0 的坏数据不会让调度崩溃', () {
      final scheduler = FsrsScheduler();
      // review_cards 的两列是 NOT NULL，导入坏数据时会以 0 出现；
      // 直接交给 fsrs 会在 Infinity.toInt() 上抛异常。
      final broken = ReviewCardState(
        dueAt: now,
        stability: 0,
        difficulty: 0,
        elapsedDays: 0,
        scheduledDays: 0,
        reps: 2,
        lapses: 1,
        fsrsState: fsrs.State.review.value,
        learningSteps: 0,
        lastReviewAt: now - dayMs,
      );

      final next = scheduler.schedule(
        card: broken,
        nowMs: now,
        rating: ReviewRating.good,
      );

      // 按新卡重来：重新取初始稳定性，回到学习态。
      expect(next.stability, greaterThan(0));
      expect(next.dueAt, greaterThan(now));
      expect(next.reps, 3);
    });
  });

  group('preview', () {
    test('恰好四项，顺序为 AGAIN/HARD/GOOD/EASY 且到期时间单调不减', () {
      final scheduler = FsrsScheduler();
      final previews = scheduler.preview(
        card: scheduler.emptyCard(now),
        nowMs: now,
      );

      expect(previews, hasLength(4));
      expect(previews.map((preview) => preview.rating).toList(), <ReviewRating>[
        ReviewRating.again,
        ReviewRating.hard,
        ReviewRating.good,
        ReviewRating.easy,
      ]);
      for (var i = 1; i < previews.length; i += 1) {
        expect(
          previews[i].nextDueAt,
          greaterThanOrEqualTo(previews[i - 1].nextDueAt),
          reason: '${previews[i].rating} 不应早于 ${previews[i - 1].rating}',
        );
        expect(
          previews[i].scheduledDays,
          greaterThanOrEqualTo(previews[i - 1].scheduledDays),
        );
      }
    });

    test('复习态卡片同样单调不减（关闭 fuzz 的意义所在）', () {
      final scheduler = FsrsScheduler();
      // 逾期 30 天、已复习过的卡片：走的是长期记忆公式与复习态分支，
      // 开启 fuzz 时 HARD 有机会被随机推到 GOOD 之后。
      final previews = scheduler.preview(
        card: reviewStateCard(elapsedDays: 30),
        nowMs: now,
      );

      expect(previews, hasLength(4));
      for (var i = 1; i < previews.length; i += 1) {
        expect(
          previews[i].nextDueAt,
          greaterThanOrEqualTo(previews[i - 1].nextDueAt),
          reason: '${previews[i].rating} 不应早于 ${previews[i - 1].rating}',
        );
      }
    });

    test('预览与真按下去的结果逐字段一致', () {
      final scheduler = FsrsScheduler();
      final card = reviewStateCard(elapsedDays: 30);

      for (final preview in scheduler.preview(card: card, nowMs: now)) {
        final scheduled = scheduler.schedule(
          card: card,
          nowMs: now,
          rating: preview.rating,
        );
        expect(preview.nextDueAt, scheduled.dueAt);
        expect(preview.scheduledDays, scheduled.scheduledDays);
      }
    });

    test('不修改传入的卡片', () {
      final scheduler = FsrsScheduler();
      final card = reviewStateCard();
      final snapshot = card.toJson();

      scheduler.preview(card: card, nowMs: now);

      expect(card.toJson(), snapshot);
    });
  });

  group('往返转换', () {
    test('复习态：fsrs 侧字段原样保留', () {
      final scheduler = FsrsScheduler();
      final original = reviewStateCard();

      final roundTripped = scheduler.fromFsrsCard(
        scheduler.toFsrsCard(original),
        previous: original,
        rating: ReviewRating.good,
        nowMs: original.lastReviewAt!,
      );

      expect(roundTripped.fsrsState, original.fsrsState);
      expect(roundTripped.learningSteps, original.learningSteps);
      expect(roundTripped.lastReviewAt, original.lastReviewAt);
      expect(roundTripped.dueAt, original.dueAt);
      expect(roundTripped.stability, original.stability);
      expect(roundTripped.difficulty, original.difficulty);
      // 派生字段：Dart 版 Card 不保存它们，只能按 nowMs 重新推导。
      expect(roundTripped.scheduledDays, original.scheduledDays);
      expect(roundTripped.elapsedDays, original.elapsedDays);
      expect(roundTripped.reps, original.reps + 1);
      expect(roundTripped.lapses, original.lapses);
    });

    test('学习态：learningSteps 与上次复习时间原样保留', () {
      final scheduler = FsrsScheduler();
      final original = learningStateCard();

      final roundTripped = scheduler.fromFsrsCard(
        scheduler.toFsrsCard(original),
        previous: original,
        rating: ReviewRating.good,
        nowMs: original.lastReviewAt!,
      );

      expect(roundTripped.fsrsState, fsrs.State.learning.value);
      expect(roundTripped.learningSteps, original.learningSteps);
      expect(roundTripped.lastReviewAt, original.lastReviewAt);
      expect(roundTripped.scheduledDays, original.scheduledDays);
    });

    test('New 态往返仍是 New，不会退化成学习态', () {
      final scheduler = FsrsScheduler();
      final empty = scheduler.emptyCard(now);

      final roundTripped = scheduler.fromFsrsCard(
        scheduler.toFsrsCard(empty),
        previous: empty,
        rating: ReviewRating.good,
        nowMs: now,
      );

      expect(roundTripped.fsrsState, 0);
      expect(roundTripped.learningSteps, 0);
      expect(roundTripped.lastReviewAt, isNull);
    });

    test('重学态往返保持状态序号', () {
      final scheduler = FsrsScheduler();
      final relearning = ReviewCardState(
        dueAt: now + 10 * minuteMs,
        stability: 2.77,
        difficulty: 5.5,
        elapsedDays: 0,
        scheduledDays: 0,
        reps: 4,
        lapses: 1,
        fsrsState: fsrs.State.relearning.value,
        learningSteps: 0,
        lastReviewAt: now,
      );

      final roundTripped = scheduler.fromFsrsCard(
        scheduler.toFsrsCard(relearning),
        previous: relearning,
        rating: ReviewRating.good,
        nowMs: now,
      );

      expect(roundTripped.fsrsState, fsrs.State.relearning.value);
      expect(roundTripped.learningSteps, relearning.learningSteps);
      expect(roundTripped.lastReviewAt, now);
    });
  });

  group('保持率夹取', () {
    test('0.1 与 5.0 不抛异常，且等价于区间端点', () {
      final card = FsrsScheduler().emptyCard(now);
      final tooLow = FsrsScheduler(requestRetention: 0.1);
      final atMin = FsrsScheduler(requestRetention: minRetentionRate);
      final tooHigh = FsrsScheduler(requestRetention: 5);
      final atMax = FsrsScheduler(requestRetention: maxRetentionRate);

      final lowPreview = tooLow.preview(card: card, nowMs: now);
      final minPreview = atMin.preview(card: card, nowMs: now);
      final highPreview = tooHigh.preview(card: card, nowMs: now);
      final maxPreview = atMax.preview(card: card, nowMs: now);

      expect(lowPreview, hasLength(4));
      for (var i = 0; i < lowPreview.length; i += 1) {
        expect(lowPreview[i].nextDueAt, minPreview[i].nextDueAt);
        expect(highPreview[i].nextDueAt, maxPreview[i].nextDueAt);
      }
      // 保持率越高，间隔越短——夹取真的生效了。
      expect(minPreview.last.nextDueAt, greaterThan(maxPreview.last.nextDueAt));
    });
  });
}
