/// 移动端触觉反馈（Haptics）统一令牌。
///
/// 集中封装的原因：
/// 1. 业务页面直接调 `HapticFeedback` 会把「用哪一档震动」散落在几十个点击回调里；
/// 2. 语义化命名（选择切换、轻微点击、主要操作、警告/错误）让全应用手感一致；
/// 3. 平台通道在测试或不支持设备上可能抛异常，这里统一静默吞掉通道级非致命忽略，
///    或者直接委托给 `HapticFeedback`（Flutter 内部已在非支持平台空实现）。
library;

import 'dart:async';

import 'package:flutter/services.dart';

/// 触觉反馈语义动作。
abstract final class LexiHaptics {
  /// 切换 Tab、分段器、筛选胶囊或拨盘时的刻度感。
  static void selection() {
    unawaited(HapticFeedback.selectionClick());
  }

  /// 轻柔触感：揭示答案、点击卡片、勾选选项、答对题目。
  static void light() {
    unawaited(HapticFeedback.lightImpact());
  }

  /// 中等触感：提交主操作、完成一组复习、答错提醒、滑出左滑菜单。
  static void medium() {
    unawaited(HapticFeedback.mediumImpact());
  }

  /// 强烈触感：执行破坏性删除、清空或重置操作。
  static void heavy() {
    unawaited(HapticFeedback.heavyImpact());
  }
}
