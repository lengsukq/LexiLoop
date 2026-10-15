/// 选择题选项。
///
/// 选中只记录、不提交：用户需要能改主意，提交必须是一次显式动作
/// （旧版在点击选项时直接提交，误触即计入一次错误作答）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_type.dart';

/// 选项在提交前后的四种外观。
enum _OptionState {
  /// 未选中。
  idle,

  /// 已选中但未提交。
  selected,

  /// 提交后判定为正确项。
  correct,

  /// 提交后被用户选中的错误项。
  wrong,
}

/// 选择题选项。
class ChoiceOptions extends StatefulWidget {
  /// 以题目、判定结果与作答回调构造。
  const new({
    required this.item,
    required this.outcome,
    required this.onAnswer,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 已提交的判定结果；未提交时为 `null`。
  final ReviewOutcome? outcome;

  /// 选中项变化时回调。
  final ValueChanged<String> onAnswer;

  @override
  State<ChoiceOptions> createState() => _ChoiceOptionsState();
}

class _ChoiceOptionsState extends State<ChoiceOptions> {
  String? _selected;

  @override
  Widget build(BuildContext context) {
    if (widget.item.choices.isEmpty) return const _MissingChoices();
    final outcome = widget.outcome;
    return Column(
      children: <Widget>[
        for (final choice in widget.item.choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _ChoiceTile(
              label: choice,
              definition: widget.item.choiceDefinitions[choice],
              state: _stateOf(choice, outcome),
              onTap: outcome == null ? () => _select(choice) : null,
            ),
          ),
      ],
    );
  }

  /// 选中：只记录并上报，**不立即提交**——用户需要能改主意。
  void _select(String choice) {
    setState(() => _selected = choice);
    widget.onAnswer(choice);
  }

  /// 提交后由 `expectedAnswer` 反查正确项。
  ///
  /// 判题只看用户作答文本与词条，界面拿不到「哪个选项对」，但服务层回传的
  /// `expectedAnswer` 恰好等于正确选项的文本（看词选义是释义串，看义选词
  /// 是词条本身），因此可以据此高亮。
  _OptionState _stateOf(String choice, ReviewOutcome? outcome) {
    if (outcome == null) {
      return choice == _selected ? _OptionState.selected : _OptionState.idle;
    }
    if (choice == outcome.expectedAnswer) return _OptionState.correct;
    if (choice == _selected) return _OptionState.wrong;
    return _OptionState.idle;
  }
}

/// 单个选项。
class _ChoiceTile extends StatelessWidget {
  const new({
    required this.label,
    required this.definition,
    required this.state,
    required this.onTap,
  });

  final String label;
  final String? definition;
  final _OptionState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    final foreground = switch (state) {
      _OptionState.idle => colors.label,
      _OptionState.selected => colors.accent,
      _OptionState.correct => colors.success,
      _OptionState.wrong => colors.danger,
    };
    final background = switch (state) {
      _OptionState.idle => colors.fill,
      _OptionState.selected => colors.accent.withValues(alpha: 0.14),
      _OptionState.correct => colors.success.withValues(alpha: 0.16),
      _OptionState.wrong => colors.danger.withValues(alpha: 0.16),
    };

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(LexiRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LexiRadius.md),
            border: Border.all(color: foreground.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                label,
                style: LexiType.title.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (definition case final text?) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  text,
                  style: LexiType.footnote.copyWith(
                    color: colors.secondaryLabel,
                  ),
                ),
              ],
            ],
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
