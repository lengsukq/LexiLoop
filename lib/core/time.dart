/// 统一的时间单位常量（毫秒）。
///
/// 与旧版 `src/lib/time.ts` 一一对应：旧版把时间单位集中在一处，
/// 避免魔法数字散落各模块。本文件保持同一约束。
library;

/// 一毫秒。
const int millisecondMs = 1;

/// 一秒的毫秒数。
const int secondMs = 1000 * millisecondMs;

/// 一分钟的毫秒数。
const int minuteMs = 60 * secondMs;

/// 一小时的毫秒数。
const int hourMs = 60 * minuteMs;

/// 一天的毫秒数。
///
/// 注意：这是固定 24 小时的时长，**不是**日历天的长度。
/// 跨日判定请使用 `date_key.dart` 的 `localDayOrdinal`，
/// 它会正确处理夏令时导致的 23/25 小时日。
const int dayMs = 24 * hourMs;

/// 一周的毫秒数。
const int weekMs = 7 * dayMs;
