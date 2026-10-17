/// 普通确认对话框：破坏性或批量动作的统一入口。
///
/// 与 `features/settings/typed_confirm_dialog.dart` 的分工：
///
/// | 强度 | 用于 | 构件 |
/// |---|---|---|
/// | 打字确认 | 不可逆且作用域大：导入全量备份、从远端恢复、清空数据、全量重新生成 | `TypedConfirmDialog` |
/// | 点击确认 | 批量写库、删除单条、覆盖已有内容 | 本文件的 [confirmAction] |
/// | 不确认但可撤销 | 单条删除后又立即给出「撤销」 | 调用方 + `SnackBarAction` |
///
/// **为什么需要一条明确的分界线**：收敛前同一类动作有着完全不同的谨慎度——
/// 「重置学习进度」在文章导入流程里勾选即生效（`article_strategy_card.dart`），
/// 在 CSV 导入流程里却要走一个对话框（`import_page.dart`）；
/// 「批量确认加入」零确认写库，「创建初始化任务」却要过一遍带预览的配置器。
/// 用户学到的规则是「这里不用确认」，然后在另一条路径上丢数据。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 弹出一个普通确认对话框；确认返回 `true`，取消或点外部返回 `false`。
///
/// [body] 必须说清三件事：**做什么**、**作用范围**（多少条 / 哪些数据）、
/// **能不能撤销**。只说「确定要删除吗？」的对话框等于没问。
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final colors = context.lexiColors;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(
        body,
        style: LexiType.body.copyWith(color: colors.secondaryLabel),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
