/// 熟练度评分与掌握等级的单元测试。
///
/// 评分公式的每个分项都有独立权重，整体又被可提取性衰减缩放；
/// 这里对「分项边界」「衰减」「等级门槛」分别断言，
/// 避免调参时只有总分变化而看不出是哪一项变了。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/review/mastery.dart';

/// 构造一个「全满」的输入，便于按需覆盖单个字段。
MasteryInput _input({
  double stability = 365,
  int scheduledDays = 100,
  int reps = 20,
  int lapses = 0,
  double accuracy = 1,
  int consecutiveCorrect = 5,
  bool activeWrongWord = false,
  int recentAgain = 0,
  double? averageDurationMs,
  int? elapsedDays,
}) => MasteryInput(
  stability: stability,
  scheduledDays: scheduledDays,
  reps: reps,
  lapses: lapses,
  accuracy: accuracy,
  consecutiveCorrect: consecutiveCorrect,
  activeWrongWord: activeWrongWord,
  recentAgain: recentAgain,
  averageDurationMs: averageDurationMs,
  elapsedDays: elapsedDays,
);

void main() {
  group('calculateRetrievability', () {
    test('刚复习完（0 天）时为 1.0', () {
      expect(calculateRetrievability(0, 10), 1);
    });

    test('稳定性非正时退化为 1.0', () {
      expect(calculateRetrievability(5, 0), 1);
      expect(calculateRetrievability(5, -1), 1);
    });

    test('恰好到期（t = S）时为 0.9', () {
      expect(calculateRetrievability(10, 10), closeTo(0.9, 1e-9));
    });

    test('严重逾期时被下限截住', () {
      expect(calculateRetrievability(100000, 1), retrievabilityFloor);
    });

    test('随时间单调不增', () {
      var previous = calculateRetrievability(0, 30);
      for (var days = 1; days <= 200; days += 7) {
        final current = calculateRetrievability(days, 30);
        expect(current, lessThanOrEqualTo(previous));
        previous = current;
      }
    });
  });

  group('calculateMasteryScore', () {
    test('从未复习过为 0 分', () {
      expect(calculateMasteryScore(_input(reps: 0)), 0);
    });

    test('六项满分且无速度加成时为 90（速度占 10 分）', () {
      expect(calculateMasteryScore(_input()), 90);
    });

    test('不传平均耗时时不给速度加成', () {
      expect(
        calculateMasteryScore(
          _input(averageDurationMs: masterySpeedBaselineMs),
        ),
        90,
      );
      expect(calculateMasteryScore(_input()), 90);
    });

    test('速度越快分越高', () {
      final fast = calculateMasteryScore(_input(averageDurationMs: 1000));
      final slow = calculateMasteryScore(_input(averageDurationMs: 14000));
      expect(fast, greaterThan(slow));
    });

    test('速度加成不超过满分权重', () {
      final instant = calculateMasteryScore(_input(averageDurationMs: 1));
      final withoutSpeed = calculateMasteryScore(_input());
      expect(instant - withoutSpeed, lessThanOrEqualTo(masteryWeightSpeed));
    });

    test('罚分被上限截住', () {
      final capped = calculateMasteryScore(_input(lapses: 1000));
      final justAtCap = calculateMasteryScore(
        _input(lapses: (masteryPenaltyCap / masteryPenaltyPerLapse).ceil()),
      );
      expect(capped, justAtCap);
    });

    test('处于活跃错词状态会扣分', () {
      expect(
        calculateMasteryScore(_input(activeWrongWord: true)),
        lessThan(calculateMasteryScore(_input())),
      );
    });

    test('逾期会按可提取性衰减总分', () {
      final fresh = calculateMasteryScore(_input(stability: 10));
      final overdue = calculateMasteryScore(
        _input(stability: 10, elapsedDays: 1000),
      );
      expect(overdue, lessThan(fresh));
    });

    test('衰减有下限，不会把熟练度打成 0', () {
      final overdue = calculateMasteryScore(
        _input(stability: 1, elapsedDays: 100000),
      );
      expect(overdue, greaterThan(0));
    });

    test('正确率超界时被夹到 [0,1]', () {
      expect(
        calculateMasteryScore(_input(accuracy: 5)),
        calculateMasteryScore(_input()),
      );
      expect(
        calculateMasteryScore(_input(accuracy: -5)),
        calculateMasteryScore(_input(accuracy: 0)),
      );
    });

    test('分数始终落在 0–100', () {
      for (final reps in <int>[0, 1, 5, 20, 200]) {
        for (final stability in <double>[0, 0.5, 10, 365, 10000]) {
          final score = calculateMasteryScore(
            _input(reps: reps, stability: stability, lapses: 50),
          );
          expect(score, inInclusiveRange(0, 100));
        }
      }
    });
  });

  group('determineMasteryLevel', () {
    test('从未复习过是 NEW', () {
      expect(
        determineMasteryLevel(_input(reps: 0, stability: 0)),
        MasteryLevel.newWord,
      );
    });

    test('处于活跃错词状态一律是 LEARNING', () {
      expect(
        determineMasteryLevel(_input(activeWrongWord: true)),
        MasteryLevel.learning,
      );
    });

    test('复习次数不足是 LEARNING', () {
      expect(
        determineMasteryLevel(_input(reps: masteryMinReps - 1)),
        MasteryLevel.learning,
      );
    });

    test('间隔不足是 LEARNING', () {
      expect(
        determineMasteryLevel(
          _input(scheduledDays: masteryMinScheduledDays - 1),
        ),
        MasteryLevel.learning,
      );
    });

    test('高分长间隔高正确率是 MASTERED', () {
      expect(determineMasteryLevel(_input()), MasteryLevel.mastered);
    });

    test('近 30 天出现过 AGAIN 时不能进 MASTERED', () {
      expect(
        determineMasteryLevel(_input(recentAgain: 1)),
        isNot(MasteryLevel.mastered),
      );
    });

    test('间隔 10 天、正确率满分是 FAMILIAR', () {
      final level = determineMasteryLevel(
        _input(
          stability: 50,
          scheduledDays: 10,
          reps: 5,
          consecutiveCorrect: 3,
        ),
      );
      expect(level, MasteryLevel.familiar);
    });

    test('间隔够但正确率不足时降级', () {
      expect(
        determineMasteryLevel(_input(accuracy: 0.5)),
        MasteryLevel.learning,
      );
    });

    test('可显式传入分数，避免重复计算', () {
      final input = _input();
      expect(
        determineMasteryLevel(input, calculateMasteryScore(input)),
        determineMasteryLevel(input),
      );
    });

    test('显式传入低分时降为 LEARNING', () {
      expect(
        determineMasteryLevel(_input(), masteryLearningScore - 1),
        MasteryLevel.learning,
      );
    });
  });
}
