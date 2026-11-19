/// 确认操作：破坏性或批量动作的统一移动端底部确认入口。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/widgets/lexi_confirm_sheet.dart';

/// 弹出移动端底部确认抽屉；确认返回 `true`，取消或点外部返回 `false`。
///
/// [body] 必须说清三件事：**做什么**、**作用范围**（多少条 / 哪些数据）、
/// **能不能撤销**。
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool destructive = false,
  Key? confirmButtonKey,
}) => showLexiConfirmSheet(
  context,
  title: title,
  body: body,
  confirmLabel: confirmLabel,
  cancelLabel: cancelLabel,
  destructive: destructive,
  confirmButtonKey: confirmButtonKey,
);
