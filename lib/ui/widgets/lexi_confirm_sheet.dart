/// 移动端原生感底部确认抽屉（取代反移动端的手打英文口令弹窗）。
///
/// 设计考量：
/// - 在手机上强迫用户弹起键盘输入大写 `EXPORT` / `UPLOAD` / `IMPORT` 体验极差；
/// - 导出与上传本身是安全的备份动作，不应设拦截弹窗；
/// - 真正具有破坏性的操作（清空词库、覆盖导入、从远端恢复覆盖）使用底部确认抽屉，
///   以醒目的危险色按钮 + 清晰的后果说明 + 触觉反馈保护用户数据。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_haptics.dart';
import 'package:lexiloop/ui/theme/lexi_layout.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_sheet.dart';

/// 弹出底部确认抽屉；用户点击确认返回 `true`，取消或点背景返回 `false`。
Future<bool> showLexiConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool destructive = false,
  Key? confirmButtonKey,
}) async {
  if (destructive) {
    LexiHaptics.medium();
  } else {
    LexiHaptics.light();
  }
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => LexiConfirmSheet(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      confirmButtonKey: confirmButtonKey,
    ),
  );
  return result ?? false;
}

/// 底部确认抽屉组件。
class LexiConfirmSheet extends StatelessWidget {
  /// 以标题、正文与操作文案构造。
  const new({
    required this.title,
    required this.body,
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    this.destructive = false,
    this.confirmButtonKey,
    super.key,
  });

  /// 标题。
  final String title;

  /// 说明正文（说清做什么、影响范围、是否可撤销）。
  final String body;

  /// 确认按钮文案。
  final String confirmLabel;

  /// 取消按钮文案。
  final String cancelLabel;

  /// 是否为破坏性操作（决定主按钮是否使用危险色）。
  final bool destructive;

  /// 确认按钮的可选测试 Key。
  final Key? confirmButtonKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return LexiSheet(
      title: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            body,
            style: LexiType.body.copyWith(color: colors.secondaryLabel),
          ),
          const SizedBox(height: LexiSpace.s20),
          SizedBox(
            height: LexiLayout.buttonHeight,
            child: FilledButton(
              key: confirmButtonKey,
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: colors.danger,
                      foregroundColor: Colors.white,
                    )
                  : null,
              onPressed: () {
                if (destructive) {
                  LexiHaptics.heavy();
                } else {
                  LexiHaptics.light();
                }
                Navigator.of(context).pop(true);
              },
              child: Text(confirmLabel),
            ),
          ),
          const SizedBox(height: LexiSpace.s8),
          SizedBox(
            height: LexiLayout.minTapTarget,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(cancelLabel),
            ),
          ),
        ],
      ),
    );
  }
}
