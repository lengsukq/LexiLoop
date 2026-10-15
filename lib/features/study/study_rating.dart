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

/// 拿不到间隔预览时的占位符。
///
/// 与旧版一致显示 `—` 而不是留白：留白看起来像界面坏了，
/// 破折号说明「这一刻确实没有这个信息」。
const String _missingInterval = '—';

/// 四档自评按钮组。
class StudyRatingBar extends StatelessWidget {
  /// 以提示语、可用性、当前等级、间隔预览与回调构造。
  const new({
    required this.hint,
    required this.enabled,
    required this.selected,
    required this.intervals,
    required this.onSelect,
    super.key,
  });

  /// 按钮组上方的提示语。
  final String hint;

  /// 是否可点击；提交后为 `false`，此时只展示已记录的等级。
  final bool enabled;

  /// 当前（将要或已经）生效的等级。
  final ReviewRating? selected;

  /// 各等级对应的间隔文案；取不到时为空表，按钮显示占位符。
  ///
  /// 传文案而不是 `FsrsIntervalPreview`：评级条不必认识 FSRS 的模型，
  /// 换算（「今天 / N 天 / N 月 / X.X 年」四档）集中在 `study_texts.dart`。
  final Map<ReviewRating, String> intervals;

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
                  interval: intervals[rating] ?? _missingInterval,
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
    required this.interval,
    required this.onTap,
  });

  final ReviewRating rating;
  final bool selected;
  final bool enabled;
  final String interval;
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
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LexiRadius.sm),
            border: Border.all(
              color: foreground.withValues(alpha: selected ? 0.6 : 0.25),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                studyRatingLabel(rating),
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              // 间隔预览是「这一档会排到什么时候」的唯一线索，也是旧版
              // 揭示答案时唯一会变的东西——按钮上必须给它留一行。
              Text(
                interval,
                key: Key('study.rating.interval.${rating.wire}'),
                style: TextStyle(
                  color: foreground.withValues(alpha: 0.75),
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
