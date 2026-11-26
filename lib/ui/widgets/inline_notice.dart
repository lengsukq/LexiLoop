/// 内联提示条：错误、警告、信息、成功四种语气。
///
/// **为什么统一**：导入、文章、配对、小游戏与设置页此前各自实现了一段
/// 「淡红底 + 图标 + 文字」；底色透明度、圆角、图标大小与是否带动作按钮
/// 全都不一样。提示条是用户出错时唯一会读的东西，它不该每次长得不同。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 提示语气。
enum InlineNoticeTone {
  /// 中性信息。
  info,

  /// 成功。
  success,

  /// 需要注意但未失败。
  warning,

  /// 失败或危险。
  danger,
}

/// 一条内联提示。
class InlineNotice extends StatelessWidget {
  /// 以文案与语气构造。
  const new({
    required this.message,
    this.tone = InlineNoticeTone.danger,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// 提示文案。
  final String message;

  /// 语气。
  final InlineNoticeTone tone;

  /// 可选的动作文案。
  final String? actionLabel;

  /// 动作回调。
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final (Color base, Color text, IconData icon) = switch (tone) {
      InlineNoticeTone.info => (
        colors.secondary,
        colors.secondaryText,
        LucideIcons.info,
      ),
      InlineNoticeTone.success => (
        colors.success,
        colors.successText,
        LucideIcons.circleCheck,
      ),
      InlineNoticeTone.warning => (
        colors.warning,
        colors.warningText,
        LucideIcons.triangleAlert,
      ),
      InlineNoticeTone.danger => (
        colors.danger,
        colors.dangerText,
        LucideIcons.circleAlert,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s12,
        vertical: LexiSpace.s10,
      ),
      decoration: BoxDecoration(
        color: base.withValues(alpha: LexiTint.tint),
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: base.withValues(alpha: LexiTint.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 17, color: text),
          const SizedBox(width: LexiSpace.s8),
          Expanded(
            child: Text(message, style: LexiType.body.copyWith(color: text)),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(width: LexiSpace.s8),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: text,
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: LexiSpace.s10),
                visualDensity: VisualDensity.compact,
              ),
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
