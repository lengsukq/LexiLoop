/// 作答时长边界处理的单测。
///
/// `boundedActiveDurationMs` 在活跃计时器上线之后并没有退休：它是**兜底**，
/// 负责崩溃恢复、时钟回拨这类「计时器根本没跑起来」的路径。这里钉住它的
/// 三档行为，免得将来被当成重复逻辑删掉。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/review/duration.dart';

void main() {
  group('boundedActiveDurationMs', () {
    test('未测量到时长时返回 null（不是 0）', () {
      expect(boundedActiveDurationMs(null), isNull);
    });

    test('负值（时钟回拨）按 0 计', () {
      expect(boundedActiveDurationMs(-1), 0);
    });

    test('超过上限时夹到上限', () {
      expect(
        boundedActiveDurationMs(maxActiveAnswerDurationMs * 3),
        maxActiveAnswerDurationMs,
      );
    });

    test('上限之内原样返回', () {
      expect(boundedActiveDurationMs(1234), 1234);
      expect(
        boundedActiveDurationMs(maxActiveAnswerDurationMs),
        maxActiveAnswerDurationMs,
      );
    });
  });

  group('sumActiveDurations', () {
    test('忽略未测量与零值，累加其余', () {
      expect(sumActiveDurations(<int?>[null, 0, 1000, 2000]), 3000);
    });

    test('每项都先夹上界再累加', () {
      expect(
        sumActiveDurations(<int?>[maxActiveAnswerDurationMs * 2, 500]),
        maxActiveAnswerDurationMs + 500,
      );
    });
  });
}
