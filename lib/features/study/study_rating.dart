/// 学习会话的四档自评。
///
/// 自评是 FSRS 的最终输入：客观判题只负责在用户选「记得」却答错时降级为
/// 「忘了」，选「模糊」或「简单」时尊重用户判断（见
/// `domain/review/answer_evaluator.dart`）。因此这四个按钮不是装饰，
/// 而是「这道题该怎么排期」的唯一入口。
///
/// **它只在揭示答案之后出现**，点选即提交并自动进入下一题——用户先看到
/// 对错与正确答案，再说记得怎么样。旧版在作答前就摆出这排按钮，等于让用户
/// 在不知道答案时先给自己打分，也是截图里「回答正确 + 自评：忘了」的来源。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/features/study/study_layout.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

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

  /// 是否可点击；提交中为 `false`，此时只展示已记录的等级。
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
    // 窄屏 2×2：四档挤在一行时标签与间隔都会缩到读不清，拇指也按不准。
    final columns = MediaQuery.sizeOf(context).width >= studyWideMinWidth
        ? ReviewRating.values.length
        : 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          hint,
          style: LexiType.footnote.copyWith(color: colors.secondaryLabel),
        ),
        const SizedBox(height: LexiSpace.s8),
        for (
          var start = 0;
          start < ReviewRating.values.length;
          start += columns
        ) ...<Widget>[
          if (start > 0) const SizedBox(height: LexiSpace.s8),
          _RatingRow(
            slots: _slotsFor(start, columns),
            enabled: enabled,
            selected: selected,
            intervals: intervals,
            onSelect: onSelect,
          ),
        ],
      ],
    );
  }

  /// 取本行要显示的等级；超出总档数的格子用 `null` 占位。
  List<ReviewRating?> _slotsFor(int start, int columns) {
    final slots = <ReviewRating?>[];
    for (var index = start; index < start + columns; index += 1) {
      slots.add(
        index < ReviewRating.values.length ? ReviewRating.values[index] : null,
      );
    }
    return slots;
  }
}

/// 一行自评按钮；最后一格不足时用空位补齐，保证列宽恒定。
class _RatingRow extends StatelessWidget {
  const new({
    required this.slots,
    required this.enabled,
    required this.selected,
    required this.intervals,
    required this.onSelect,
  });

  /// 本行每一列要放的等级；`null` 表示这一格留空（最后一排不足四档时）。
  final List<ReviewRating?> slots;
  final bool enabled;
  final ReviewRating? selected;
  final Map<ReviewRating, String> intervals;
  final ValueChanged<ReviewRating> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var index = 0; index < slots.length; index += 1) ...<Widget>[
          Expanded(
            child: switch (slots[index]) {
              final ReviewRating rating => _RatingButton(
                rating: rating,
                selected: rating == selected,
                enabled: enabled,
                interval: intervals[rating] ?? _missingInterval,
                onTap: () => onSelect(rating),
              ),
              null => const SizedBox.shrink(),
            },
          ),
          if (index < slots.length - 1) const SizedBox(width: LexiSpace.s8),
        ],
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
    // 提交中只保留被记录的那一档的颜色，其余压暗：一眼能看出「刚才算的是哪档」。
    //
    // 压暗用 `quaternaryLabel`（4.5:1 档）而不是 `tertiaryLabel`：未作答时
    // 四档标签是页面上**唯一**的操作指引，而 tertiary 压在 `fill` 上只有
    // 1.74:1，间隔行再乘 0.75 透明度后只剩 1.50:1——最该读清的字反而最浅。
    final dimmed = !enabled && !selected;
    final foreground = dimmed ? colors.quaternaryLabel : tint;
    final background = dimmed
        ? colors.fill
        : tint.withValues(alpha: selected ? LexiTint.tint : LexiTint.subtle);

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(LexiRadius.sm),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: LexiSpace.s4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(LexiRadius.sm),
              border: Border.all(
                color: foreground.withValues(
                  alpha: selected ? LexiTint.half : LexiTint.border,
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  studyRatingLabel(rating),
                  style: LexiType.callout.copyWith(
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: LexiSpace.s2),
                // 间隔预览是「这一档会排到什么时候」的唯一线索，也是旧版
                // 揭示答案时唯一会变的东西——按钮上必须给它留一行。
                //
                // 不再乘透明度：它叠在已经压暗的前景色上会掉到 1.5:1 左右，
                // 而这一行正是用户决定「选哪档」时要看的信息。
                Text(
                  interval,
                  key: Key('study.rating.interval.${rating.wire}'),
                  style: LexiType.caption.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
