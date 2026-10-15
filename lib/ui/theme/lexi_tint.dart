/// LexiLoop 的**淡色透明度**音阶。
///
/// **为什么需要它**：收敛前 `withValues(alpha:)` 出现过 21 种取值，其中一大
/// 半是肉眼分不出的近邻——`0.06 / 0.07 / 0.08` 三档同时存在，`0.10 / 0.12 /
/// 0.14 / 0.15 / 0.16` 五档同时存在，描边则散在 `0.2 / 0.25 / 0.3 / 0.35`。
/// 同一个界面里「有的淡底是 12%、有的是 14%」不会有人指出来，但它正是
/// 「看起来不统一」的来源：眼睛读不出差别，只觉得哪里不一致。
///
/// 档位只保留**意图不同**的那几级：分组底 / 轻强调底 / 强调底 / 描边，
/// 再加大面积遮罩与游戏用的近实心底。
///
/// 用法：`colors.accent.withValues(alpha: LexiTint.tint)`。
library;

/// 淡色透明度音阶。
abstract final class LexiTint {
  /// 全透明——只用在渐变的端点（`color → 透明`）。
  static const double none = 0;

  /// 分组底（4%）——卡片内部再分组的块、引用块。
  ///
  /// 用 `label` 这类近黑色当底时，4% 大约是 `#F5F5F5`：够看出分组，
  /// 又不会让卡片显得脏。
  static const double group = 0.04;

  /// 轻强调底（6%）——弱提示、hover、非选中的「可点」暗示。
  static const double subtle = 0.06;

  /// 强调底（12%）——选中态、徽章、淡色说明块。
  static const double tint = 0.12;

  /// 淡色描边（30%）——叠在 [tint] 或 [subtle] 上，把淡底从相邻底上分开。
  static const double border = 0.30;

  /// 半透明（50%）——遮罩、波浪下划线这类装饰。
  static const double half = 0.50;

  /// 近实心（85%）——只给游戏里的方块用，要求一眼看出颜色。
  static const double strong = 0.85;
}
