/// 通用胶囊标签与状态计数芯片。
///
/// 统一替换此前散落在业务模块中的 `WordCard._CardTag`、`StudyProgressHeader._CountChip`、
/// `QueueToolbar._StatusChip` 等重复实现。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 通用状态/计数胶囊组件。
class LexiChip extends StatelessWidget {
  /// 以文案、主色与可选图标构造。
  const new({
    required this.label,
    this.color,
    this.icon,
    this.selected = false,
    super.key,
  });

  /// 胶囊显示文案。
  final String label;

  /// 语义前景色；为空时使用次级标签色。
  final Color? color;

  /// 前置小图标。
  final IconData? icon;

  /// 是否处于高亮选中态。
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final effectiveColor = color ?? colors.secondaryLabel;
    final background = color != null
        ? effectiveColor.withValues(
            alpha: selected ? LexiTint.border : LexiTint.tint,
          )
        : colors.fill;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: LexiSpace.s8,
        vertical: LexiSpace.s4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(LexiRadius.pill),
        border: selected
            ? Border.all(
                color: effectiveColor.withValues(alpha: LexiTint.border),
              )
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon case final iconData?) ...<Widget>[
            Icon(iconData, size: 13, color: effectiveColor),
            const SizedBox(width: LexiSpace.s4),
          ],
          Text(
            label,
            style: LexiType.caption.copyWith(
              color: effectiveColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
