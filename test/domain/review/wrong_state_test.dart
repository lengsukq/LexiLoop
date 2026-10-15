/// 错词状态转移的单元测试。
///
/// 错词本的进出规则直接决定「哪些词会反复出现在错题里」，
/// 最需要钉住的是**跨自然日**语义：同一天刷十遍不能解除错词。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/time.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/review/wrong_state.dart';

/// 2026-03-01 10:00 本地时间。
final int day0 = DateTime(2026, 3, 1, 10).millisecondsSinceEpoch;

/// 从 [day0] 起第 [days] 天的同一时刻。
int dayAt(int days) => day0 + days * dayMs;

WrongStateSnapshot _snapshot({
  bool active = true,
  int wrongCount = 1,
  int hardCount = 0,
  int consecutiveCorrect = 0,
  int? lastWrongAt,
  int? lastCorrectAt,
}) => WrongStateSnapshot(
  active: active,
  wrongCount: wrongCount,
  hardCount: hardCount,
  consecutiveCorrect: consecutiveCorrect,
  lastWrongAt: lastWrongAt,
  lastCorrectAt: lastCorrectAt,
);

void main() {
  group('无需落库的情形', () {
    test('从未有过记录且评为「记得」时返回 null', () {
      expect(
        transitionWrongState(
          current: null,
          rating: ReviewRating.good,
          isCorrect: true,
          now: day0,
        ),
        isNull,
      );
    });

    test('从未有过记录且评为「简单」时返回 null', () {
      expect(
        transitionWrongState(
          current: null,
          rating: ReviewRating.easy,
          isCorrect: true,
          now: day0,
        ),
        isNull,
      );
    });

    test('无记录时压缩结果等价于「不在错词本、连对 1 天」', () {
      final result = wrongStateResultOf(null);
      expect(result.active, isFalse);
      expect(result.consecutiveCorrect, 1);
    });
  });

  group('答错与模糊', () {
    test('答错记为一次错并清零连续正确', () {
      final transition = transitionWrongState(
        current: _snapshot(consecutiveCorrect: 2, lastCorrectAt: dayAt(-1)),
        rating: ReviewRating.good,
        isCorrect: false,
        now: day0,
      )!;
      expect(transition.active, isTrue);
      expect(transition.wrongCount, 2);
      expect(transition.hardCount, 0);
      expect(transition.consecutiveCorrect, 0);
      expect(transition.lastWrongAt, day0);
      expect(transition.resolvedAt, isNull);
    });

    test('评为「重来」即使客观判对也算答错', () {
      final transition = transitionWrongState(
        current: null,
        rating: ReviewRating.again,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.active, isTrue);
      expect(transition.wrongCount, 1);
    });

    test('评为「模糊」只增模糊计数，不增错误计数', () {
      final transition = transitionWrongState(
        current: _snapshot(wrongCount: 3, hardCount: 1),
        rating: ReviewRating.hard,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.active, isTrue);
      expect(transition.wrongCount, 3, reason: '「模糊」不是「错误」');
      expect(transition.hardCount, 2);
      expect(transition.consecutiveCorrect, 0);
      expect(transition.lastWrongAt, isNull, reason: '模糊不应更新上次答错时间');
    });

    test('答错会保留上次答对时间', () {
      final transition = transitionWrongState(
        current: _snapshot(lastCorrectAt: dayAt(-3)),
        rating: ReviewRating.good,
        isCorrect: false,
        now: day0,
      )!;
      expect(transition.lastCorrectAt, dayAt(-3));
    });
  });

  group('评为「简单」', () {
    test('有记录时直接解除', () {
      final transition = transitionWrongState(
        current: _snapshot(wrongCount: 5, hardCount: 2),
        rating: ReviewRating.easy,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.active, isFalse);
      expect(transition.resolvedAt, day0);
      expect(transition.consecutiveCorrect, 1);
      expect(transition.wrongCount, 5, reason: '解除不清空历史计数');
      expect(transition.lastCorrectAt, day0);
    });
  });

  group('评为「记得」时的跨日累加', () {
    test('首次答对记为连对 1 天', () {
      final transition = transitionWrongState(
        current: _snapshot(lastWrongAt: dayAt(-5)),
        rating: ReviewRating.good,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.consecutiveCorrect, 1);
    });

    test('同一天内重复答对不累加', () {
      final transition = transitionWrongState(
        current: _snapshot(consecutiveCorrect: 1, lastCorrectAt: day0),
        rating: ReviewRating.good,
        isCorrect: true,
        now: day0 + hourMs,
      )!;
      expect(transition.consecutiveCorrect, 1);
    });

    test('隔一天答对则累加', () {
      final transition = transitionWrongState(
        current: _snapshot(consecutiveCorrect: 1, lastCorrectAt: day0),
        rating: ReviewRating.good,
        isCorrect: true,
        now: dayAt(1),
      )!;
      expect(transition.consecutiveCorrect, 2);
    });

    test('中断超过一天则重新从 1 开始', () {
      final transition = transitionWrongState(
        current: _snapshot(consecutiveCorrect: 4, lastCorrectAt: day0),
        rating: ReviewRating.good,
        isCorrect: true,
        now: dayAt(5),
      )!;
      expect(transition.consecutiveCorrect, 1);
    });
  });

  group('解除条件', () {
    /// 构造「已连对 n 天、上次答错在 m 天前」的状态。
    WrongStateSnapshot ready({
      required int streak,
      required int wrongDaysAgo,
    }) => _snapshot(
      consecutiveCorrect: streak,
      lastCorrectAt: dayAt(-1),
      lastWrongAt: dayAt(-wrongDaysAgo),
    );

    test('连对 3 天且距上次答错 2 天时解除', () {
      final transition = transitionWrongState(
        current: ready(
          streak: wrongWordResolveConsecutiveDays - 1,
          wrongDaysAgo: wrongWordResolveMinDayGap,
        ),
        rating: ReviewRating.good,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.consecutiveCorrect, wrongWordResolveConsecutiveDays);
      expect(transition.active, isFalse);
      expect(transition.resolvedAt, day0);
    });

    test('连对天数不足时不解除', () {
      final transition = transitionWrongState(
        current: ready(streak: 0, wrongDaysAgo: wrongWordResolveMinDayGap),
        rating: ReviewRating.good,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.active, isTrue);
      expect(transition.resolvedAt, isNull);
    });

    test('距上次答错太近时不解除（防止一天刷题洗白）', () {
      final transition = transitionWrongState(
        current: ready(streak: 4, wrongDaysAgo: 0),
        rating: ReviewRating.good,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.active, isTrue);
      expect(transition.resolvedAt, isNull);
    });

    test('从未答错过的词条不受「距上次答错」限制', () {
      final transition = transitionWrongState(
        current: _snapshot(
          consecutiveCorrect: wrongWordResolveConsecutiveDays - 1,
          lastCorrectAt: dayAt(-1),
        ),
        rating: ReviewRating.good,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.active, isFalse);
    });

    test('已解除的词条在连对天数不足时保持解除状态', () {
      final transition = transitionWrongState(
        current: _snapshot(
          active: false,
          consecutiveCorrect: 1,
          lastCorrectAt: dayAt(-2),
          lastWrongAt: dayAt(-10),
        ),
        rating: ReviewRating.good,
        isCorrect: true,
        now: day0,
      )!;
      expect(transition.active, isFalse);
    });

    test('答错会重新激活已解除的词条', () {
      final transition = transitionWrongState(
        current: _snapshot(active: false, wrongCount: 3),
        rating: ReviewRating.good,
        isCorrect: false,
        now: day0,
      )!;
      expect(transition.active, isTrue);
      expect(transition.resolvedAt, isNull);
      expect(transition.wrongCount, 4);
    });
  });

  group('结果压缩', () {
    test('有转移时透传 active 与连对天数', () {
      final transition = transitionWrongState(
        current: null,
        rating: ReviewRating.again,
        isCorrect: false,
        now: day0,
      )!;
      final result = wrongStateResultOf(transition);
      expect(result.active, isTrue);
      expect(result.consecutiveCorrect, 0);
    });
  });
}
