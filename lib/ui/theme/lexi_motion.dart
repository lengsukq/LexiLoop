/// 动效时长与「减弱动态效果」。
///
/// **为什么需要它**：`MediaQuery.disableAnimationsOf` 是系统给应用的唯一
/// 「减弱动态效果」信号（macOS 的「辅助功能 › 显示器 › 减少动态效果」、
/// iOS 的同名开关）。应用自己的动画如果直接写死时长，就等于忽略了这个开关。
///
/// HIG 的 `motion.md` 要求：开启减弱动态效果后，**非必要的**位移动画与缩放
/// 动画要取消，只保留淡入淡出这类不引起前庭不适的变化。本项目只有一处这类
/// 动画（打地鼠的出现缩放），一律走 [LexiMotion.of]。
library;

import 'package:flutter/widgets.dart';

/// 动效时长。
abstract final class LexiMotion {
  /// 即时反馈（出现 / 消失 / 状态切换）的时长。
  static const Duration feedback = Duration(milliseconds: 160);

  /// 把 [duration] 按系统的「减弱动态效果」折成零。
  ///
  /// 返回 `Duration.zero` 而不是跳过动画本身：隐式动画组件收到零时长会
  /// 直接落到终态，语义与「立即出现」一致，也不需要调用方写分支。
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
