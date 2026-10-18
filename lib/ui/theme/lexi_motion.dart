/// 动效时长与「减弱动态效果」。
///
/// **为什么需要它**：`MediaQuery.disableAnimationsOf` 是系统给应用的唯一
/// 「减弱动态效果」信号（macOS 的「辅助功能 › 显示器 › 减少动态效果」、
/// iOS 的同名开关）。应用自己的动画如果直接写死时长，就等于忽略了这个开关。
///
/// HIG 的 `motion.md` 要求：开启减弱动态效果后，**非必要的**位移动画与缩放
/// 动画要取消，只保留淡入淡出这类不引起前庭不适的变化。
library;

import 'package:flutter/widgets.dart';

/// 动效时长与曲线。
abstract final class LexiMotion {
  /// 即时反馈（按压、选中态切换）。
  static const Duration quick = Duration(milliseconds: 120);

  /// 标准时长（展开、主题切换、内容切换）。
  static const Duration standard = Duration(milliseconds: 220);

  /// 强调时长（页面转场、完成反馈）。
  static const Duration emphasized = Duration(milliseconds: 320);

  /// 旧名保留：即时反馈。
  static const Duration feedback = quick;

  /// 旧名保留：状态切换。
  static const Duration change = standard;

  /// iOS 式「快到慢」的收尾曲线：起步快、末端稳，适合按压与卡片入场。
  static const Curve spring = Cubic(0.16, 1, 0.3, 1);

  /// 分区入场的单档延迟与上限。
  static const Duration staggerStep = Duration(milliseconds: 40);

  /// 分区入场的最大延迟。
  static const Duration staggerMax = Duration(milliseconds: 120);

  /// 第 [index] 个分区的入场延迟。
  static Duration stagger(int index) {
    final delay = staggerStep * index;
    return delay > staggerMax ? staggerMax : delay;
  }

  /// 把 [duration] 按系统的「减弱动态效果」折成零。
  ///
  /// 返回 `Duration.zero` 而不是跳过动画本身：隐式动画组件收到零时长会
  /// 直接落到终态，语义与「立即出现」一致，也不需要调用方写分支。
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;

  /// 按压缩放比例；减弱动态效果时调用方应跳过缩放。
  static const double pressScale = 0.98;
}
