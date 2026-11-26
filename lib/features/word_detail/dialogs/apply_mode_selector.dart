/// 「应用方式」二选一。
///
/// 对应旧版 `youdao-preview-dialog.tsx` 与 `edit-word-dialog.tsx` 里
/// 各写一遍的那组单选框。两处文案必须逐字相同——同一个选择在两个入口
/// 给出两种解释，用户会以为是两件不同的事。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 「仅补全缺失字段」的说明。
const String fillMissingHint = '保留现有内容，只用有道结果填充空缺部分。';

/// 「覆盖替换」的说明。
///
/// 必须写明保留用户资产：不写的话用户会以为「覆盖」连自己手写的释义
/// 一起清掉，于是永远不敢点它。
const String forceOverwriteHint = '用有道结果替换现有内容，但保留手动编辑的释义和手动添加的例句。';

/// 应用方式选择器。
class ApplyModeSelector extends StatelessWidget {
  /// 以当前选择与变更回调构造。
  const new({required this.mode, required this.onChanged, super.key});

  /// 当前选择。
  final InitializationMode mode;

  /// 选择变更回调。
  final ValueChanged<InitializationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      padding: const EdgeInsets.all(LexiSpace.s12),
      decoration: BoxDecoration(
        color: colors.label.withValues(alpha: LexiTint.group),
        borderRadius: BorderRadius.circular(LexiRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '应用方式',
            style: LexiType.body.copyWith(
              color: colors.label,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: LexiSpace.s6),
          _ModeOption(
            label: '仅补全缺失字段',
            hint: fillMissingHint,
            selected: mode == InitializationMode.fillMissingFields,
            onTap: () => onChanged(InitializationMode.fillMissingFields),
          ),
          _ModeOption(
            label: '覆盖替换',
            hint: forceOverwriteHint,
            selected: mode == InitializationMode.forceOverwrite,
            onTap: () => onChanged(InitializationMode.forceOverwrite),
          ),
        ],
      ),
    );
  }
}

/// 一个应用方式选项。
class _ModeOption extends StatelessWidget {
  const new({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              selected ? LucideIcons.circleDot : LucideIcons.circle,
              size: 18,
              color: selected ? colors.accent : colors.tertiaryLabel,
            ),
            const SizedBox(width: LexiSpace.s8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: LexiType.body.copyWith(
                      color: colors.label,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    hint,
                    style: LexiType.footnote.copyWith(
                      color: colors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
