/// 选择题选项。
///
/// **选中即揭示，由页面决定**：本组件只把点击翻译成 `onSelect`，是否锁定、
/// 是否揭示、是否正确由学习页与领域判题决定。这样「点错一个选项就记一次
/// 错误作答」不会发生——揭示不写库，写库仍只在自评时发生。
///
/// 揭示后选项不可再改选（与 Next 版一致）：否则用户可以先看对错再改答案，
/// 会话里的正确率就失去意义。误触的出口是自评「忘了」。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_texts.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
import 'package:lexiloop/ui/theme/lexi_tint.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';
import 'package:lexiloop/ui/widgets/lexi_pressable.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// 选项在揭示前后的五种外观。
enum _OptionState {
  /// 未选中，且尚未揭示。
  idle,

  /// 已选中，尚未揭示。
  selected,

  /// 揭示后：正确项。
  correct,

  /// 揭示后：被选中的错误项。
  wrong,

  /// 揭示后：既不对也未选的其余项。
  muted,
}

/// 选择题选项。
class ChoiceOptions extends StatelessWidget {
  /// 以题目、当前选中项、是否已揭示与选择回调构造。
  const new({
    required this.item,
    required this.selected,
    required this.revealed,
    required this.onSelect,
    this.definitionStyle = ChoiceDefinitionStyle.full,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 当前选中的选项；未作答时为 `null`。
  final String? selected;

  /// 是否已经揭示答案。
  final bool revealed;

  /// 选中某项时回调。
  final ValueChanged<String> onSelect;

  /// 控制未揭示选项的展示密度，正确答案仍使用完整原文。
  final ChoiceDefinitionStyle definitionStyle;

  @override
  Widget build(BuildContext context) {
    if (item.choices.isEmpty) return const _MissingChoices();
    final correct = studyChoiceAnswer(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final (index, choice) in item.choices.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s8),
            child: _ChoiceTile(
              index: index + 1,
              label: choice,
              displayLabel: revealed && choice == correct
                  ? choice
                  : studyChoicePreview(choice, definitionStyle),
              definition: revealed ? item.choiceDefinitions[choice] : null,
              state: _stateOf(choice, correct),
              onTap: revealed ? null : () => onSelect(choice),
            ),
          ),
      ],
    );
  }

  _OptionState _stateOf(String choice, String correct) {
    if (!revealed) {
      return choice == selected ? _OptionState.selected : _OptionState.idle;
    }
    if (choice == correct) return _OptionState.correct;
    if (choice == selected) return _OptionState.wrong;
    return _OptionState.muted;
  }
}

/// 单个选项。
///
/// **为什么不用 `Surface`**：`Surface` 的底与描边是固定的，而选项有五种状态色。
/// 这里保留自绘容器，但取值全部来自 token（圆角 `md`、间距 `LexiSpace`、
/// 文字 `LexiType`、透明度 `LexiTint`）。
class _ChoiceTile extends StatelessWidget {
  const new({
    required this.index,
    required this.label,
    required this.displayLabel,
    required this.definition,
    required this.state,
    required this.onTap,
  });

  final int index;
  final String label;
  final String displayLabel;
  final String? definition;
  final _OptionState state;
  final VoidCallback? onTap;

  /// 选项行的最小高度。
  ///
  /// 高于 macOS 的 28：选项是这一页的主要点击目标，且移动端要满足 44 的
  /// 触控下限——两行文字（词条 + 释义）本来也需要这么高。
  static const double minHeight = 56;

  /// 选中态的描边宽度；其余状态一律 1px。
  static const double selectedBorderWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, border) = _tileColors(context);
    return Semantics(
      button: true,
      selected: state == _OptionState.selected,
      child: LexiPressable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LexiRadius.lg),
        child: Container(
          constraints: const BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s16,
            vertical: LexiSpace.s16,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(LexiRadius.lg),
            border: Border.all(
              color: border,
              width: state == _OptionState.selected ? selectedBorderWidth : 1,
            ),
          ),
          child: _contentRow(context, foreground),
        ),
      ),
    );
  }

  /// 五种状态对应的文字 / 底色 / 描边。
  ///
  /// 文字色用 `*Text` 系列：饱和色当文字压在淡底上只有 1.8–3.3:1。
  (Color, Color, Color) _tileColors(BuildContext context) {
    final colors = context.lexiColors;
    return switch (state) {
      _OptionState.idle => (colors.label, colors.card, colors.borderSubtle),
      _OptionState.selected => (
        colors.accentText,
        colors.accent.withValues(alpha: LexiTint.subtle),
        colors.accent,
      ),
      _OptionState.correct => (
        colors.successText,
        colors.success.withValues(alpha: LexiTint.tint),
        colors.success,
      ),
      _OptionState.wrong => (
        colors.dangerText,
        colors.danger.withValues(alpha: LexiTint.tint),
        colors.danger,
      ),
      // 压暗用 `quaternaryLabel`（4.5:1 档）而不是 tertiary + opacity：
      // 揭示后其余选项仍然要能读清，只是不该抢走注意力。
      _OptionState.muted => (
        colors.quaternaryLabel,
        colors.card,
        colors.borderSubtle,
      ),
    };
  }

  /// 序号 + 判定图标 + 选项文字与释义。
  Widget _contentRow(BuildContext context, Color foreground) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ShortcutBadge(number: index, color: foreground),
        const SizedBox(width: LexiSpace.s12),
        // 判定结果额外给一个图标：颜色不能是唯一的信号
        // （HIG `accessibility.md`：不要只靠颜色传达信息）。
        if (_resultIcon case final icon?) ...<Widget>[
          Padding(
            padding: const EdgeInsets.only(top: LexiSpace.s2),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const SizedBox(width: LexiSpace.s8),
        ],
        Expanded(child: _labels(context, foreground)),
      ],
    );
  }

  /// 选项文字与释义。
  Widget _labels(BuildContext context, Color foreground) {
    final text = definition;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Tooltip(
          message: label,
          child: Text(
            displayLabel,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: LexiType.callout.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
        ),
        if (text != null && text.isNotEmpty) ...<Widget>[
          const SizedBox(height: LexiSpace.s2),
          Text(
            text,
            style: LexiType.footnote.copyWith(
              color: context.lexiColors.secondaryLabel,
            ),
          ),
        ],
      ],
    );
  }

  /// 判定结果对应的图标；未判定时为 `null`。
  IconData? get _resultIcon => switch (state) {
    _OptionState.correct => LucideIcons.circleCheck,
    _OptionState.wrong => LucideIcons.circleX,
    _ => null,
  };
}

/// 选项前的数字序号（对应快捷键 `1`–`4`）。
class _ShortcutBadge extends StatelessWidget {
  const new({required this.number, required this.color});

  final int number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: LexiTint.subtle),
        borderRadius: BorderRadius.circular(LexiRadius.sm),
      ),
      child: ExcludeSemantics(
        child: Text(
          String.fromCharCode(64 + number),
          style: LexiType.caption.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 选项缺失时的兜底提示。
class _MissingChoices extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Text(
      '该词条暂无可用选项，可先跳过本题',
      style: LexiType.body.copyWith(color: colors.secondaryLabel),
    );
  }
}
