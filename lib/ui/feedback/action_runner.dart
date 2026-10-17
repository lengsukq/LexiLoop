/// 动作执行器：所有「写库 / 调外部服务」的动作都从这里过一遍。
///
/// **为什么需要它**：收敛前，设置页的 14 处 `saveSettings` 全部写成
/// `unawaited(saveSettings(...))`——
///
/// * 写失败没有任何提示：开关看起来已经切过去了，数据库里还是旧值，
///   下次冷启动又弹回来，用户只会觉得「这个设置不生效」；
/// * 没有 `catch`，异常被 `unawaited` 无声吞掉，日志里也没有痕迹；
/// * 每一处都要自己拼 `try/catch + ScaffoldMessenger`，于是大部分地方
///   干脆不拼。
///
/// 这里把三件事收在一处：**等待**、**归一化错误**、**在界面上给出结果**。
/// 返回 `bool` 让调用方可以回滚乐观更新（`if (!ok) setState(旧值)`）。
///
/// 注意：本函数不负责「确认」。确认的分级见
/// `lib/ui/feedback/confirm_dialog.dart` 的说明。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/core/errors.dart';

/// 执行 [action]，把成功 / 失败结果反馈到界面上。
///
/// * [successMessage] 非空时，成功后弹一条 SnackBar；
/// * [failureLabel] 会拼在失败原因前面，例如「导出失败：」；
/// * 抛出的异常一律经 [normalizeError] 转成面向用户的中文。
Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
  String failureLabel = '操作失败',
}) async {
  try {
    await action();
  } on Object catch (error) {
    if (!context.mounted) return false;
    _notify(context, '$failureLabel：${normalizeError(error).message}');
    return false;
  }
  if (!context.mounted) return true;
  if (successMessage != null) _notify(context, successMessage);
  return true;
}

/// 只反馈失败、不反馈成功的变体。
///
/// 用于高频动作（切一个开关、拖一次滑杆）：每次都弹「已保存」是噪声，
/// 但失败必须说话。
Future<bool> runQuietly(
  BuildContext context,
  Future<void> Function() action, {
  String failureLabel = '保存失败',
}) => runGuarded(context, action, failureLabel: failureLabel);

/// 弹一条提示，替换掉上一条。
void _notify(BuildContext context, String message) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
}
