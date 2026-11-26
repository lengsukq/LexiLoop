/// 本地时区的「日历日」工具。
///
/// **与旧版的差异**：旧版服务端用环境变量 `APP_TIMEZONE`（固定 `Asia/Shanghai`）
/// 决定日界；纯本地应用没有服务端时区概念，改用**设备本地时区**。
/// 对身处中国的使用者两者等价；跨时区旅行时日界会跟随设备，这是本地应用的正确行为。
///
/// 错词解除（需跨连续自然日）、每日队列配额、学习连续天数都依赖这里的日界语义，
/// 因此所有「跨日」判断必须走本模块，不得直接用 `dayMs` 相减。
library;

import 'package:lexiloop/core/time.dart';

/// 一天的自 1970-01-01 起的毫秒数，用于把日期折算成日序数。
const int _msPerDay = dayMs;

/// 本地时区日期键，形如 `2026-08-08`。
///
/// 用作按天聚合的 Map 键与数据库中的 `date_key` 列。
String dateKey(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// 本地时区当天零点的时间戳。
///
/// 用 `DateTime` 构造而非减去余数，以正确处理夏令时切换日。
int startOfLocalDay(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
}

/// 前一天的日期键。
String previousDateKey(int now) => dateKey(now - dayMs);

/// 本地时区的日序数（自 1970-01-01 起的天数），用于跨日间隔计算。
///
/// 先把本地年月日搬到 UTC 再取整，避免本地时区偏移与夏令时影响差值。
int localDayOrdinal(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final utcMidnight = DateTime.utc(date.year, date.month, date.day);
  return utcMidnight.millisecondsSinceEpoch ~/ _msPerDay;
}
