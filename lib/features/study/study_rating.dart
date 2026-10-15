/// 学习会话的四档自评。
///
/// 自评是 FSRS 的最终输入：客观判题只负责在用户选「记得」却答错时降级为
/// 「忘了」，选「模糊」或「简单」时尊重用户判断（见
/// `domain/review/answer_evaluator.dart`）。因此这四个按钮不是装饰，
/// 而是「这道题该怎么排期」的唯一入口。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 四档自评按钮组。
class StudyRatingBar extends StatelessWidget {
  /// 以提示语、可用性、当前等级与回调构造。
  const new({
    required this.hint,
    required this.enabled,
    required this.selected,
    required this.onSelect,
    super.key,
  });

  /// 按钮组上方的提示语。
  final String hint;

  /// 是否可点击；提交后为 `false`，此时只展示已记录的等级。
  final bool enabled;

  /// 当前（将要或已经）生效的等级。
  final ReviewRating? selected;

  /// 选择回调。
  final ValueChanged<ReviewRating> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          hint,
          style: TextStyle(color: colors.secondaryLabel, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            for (final rating in ReviewRating.values) ...<Widget>[
              Expanded(
                child: _RatingButton(
                  rating: rating,
                  selected: rating == selected,
                  enabled: enabled,
                  onTap: () => onSelect(rating),
                ),
              ),
              if (rating != ReviewRating.values.last) const SizedBox(width: 8),
            ],
          ],
        ),
      ],
    );
  }
}

/// 单个自评按钮。
class _RatingButton extends StatelessWidget {
  const new({
    required this.rating,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final ReviewRating rating;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final tint = switch (rating) {
      ReviewRating.again => colors.danger,
      ReviewRating.hard => colors.warning,
      ReviewRating.good => colors.accent,
      ReviewRating.easy => colors.success,
    };
    // 已提交时只保留被记录的那一档的颜色，其余压暗：一眼能看出「刚才算的是哪档」。
    final dimmed = !enabled && !selected;
    final foreground = dimmed ? colors.tertiaryLabel : tint;
    final background = dimmed
        ? colors.fill
        : tint.withValues(alpha: selected ? 0.18 : 0.08);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LexiRadius.sm),
            border: Border.all(
              color: foreground.withValues(alpha: selected ? 0.6 : 0.25),
            ),
          ),
          child: Text(
            studyRatingLabel(rating),
            style: TextStyle(
              color: foreground,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
