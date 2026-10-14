/// 作答时长与学习时长的边界处理。
///
/// 对应旧版 `modules/reviews/duration.ts`。
///
/// **为什么需要上界**：移动端切后台、页面离屏、用户中途离开都会让
/// 「本题耗时」变成几十分钟。旧版统计页的时长因此严重虚高；
/// 超过 [maxActiveAnswerDurationMs] 一律按上限计。
library;

import 'package:lexiloop/core/constants.dart';

/// 把作答耗时夹到 `[0, maxActiveAnswerDurationMs]`；无效值返回 `null`。
///
/// 返回 `null` 与返回 `0` 语义不同：`null` 表示「没有测量到」，
/// 统计平均耗时时必须排除；`0` 表示「测到了，但很快」。
int? boundedActiveDurationMs(int? value) {
  if (value == null) return null;
  if (value < 0) return 0;
  return value > maxActiveAnswerDurationMs ? maxActiveAnswerDurationMs : value;
}

/// 把一组作答耗时累加为有效学习时长。
int sumActiveDurations(Iterable<int?> durations) {
  var total = 0;
  for (final duration in durations) {
    final bounded = boundedActiveDurationMs(duration);
    if (bounded != null && bounded > 0) total += bounded;
  }
  return total;
}
