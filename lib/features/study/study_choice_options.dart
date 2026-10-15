/// 选择题选项。
///
/// 选中只记录、不提交：用户需要能改主意，提交必须是一次显式动作
/// （旧版在点击选项时直接提交，误触即计入一次错误作答）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';
import 'package:lexiloop/ui/theme/lexi_space.dart';
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
    // `crossAxisAlignment` 必须是 stretch：`Column` 默认是 center，而选项
    // 没有固定宽度，于是每个选项会按自身文字宽度收缩、再被居中，呈现为
    // 一列长短不一的胶囊。选项是一组同构的选择，必须等宽、左对齐，眼睛才
    // 能沿一条竖线扫下来（HIG `layout.md`：对齐让内容更易扫读）。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final choice in widget.item.choices)
          Padding(
            padding: const EdgeInsets.only(bottom: LexiSpace.s8),
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
///
/// **为什么不用 `Surface`**：`Surface` 的底与描边是固定的，而选项有
/// idle / selected / correct / wrong 四种状态色。这里保留自绘容器，但取值
/// 全部来自 token（圆角 `md`、间距 `LexiSpace`、文字 `LexiType`）。
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

  /// 选项行的最小高度。
  ///
  /// 高于 macOS 的 28：选项是这一页的主要点击目标，且移动端要满足 44 的
  /// 触控下限——两行文字（词条 + 释义）本来也需要这么高。
  static const double minHeight = 56;

  /// 选中态的描边宽度；其余状态一律 1px。
  static const double selectedBorderWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    // 文字色用 `*Text` 系列：饱和色当文字压在淡底上只有 1.8–3.3:1。
    final (foreground, background, border) = switch (state) {
      _OptionState.idle => (colors.label, colors.fill, colors.borderDefault),
      _OptionState.selected => (
        colors.accentText,
        colors.accent.withValues(alpha: 0.06),
        colors.accent,
      ),
      _OptionState.correct => (
        colors.successText,
        colors.success.withValues(alpha: 0.10),
        colors.success,
      ),
      _OptionState.wrong => (
        colors.dangerText,
        colors.danger.withValues(alpha: 0.10),
        colors.danger,
      ),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: LexiSpace.s16,
            vertical: LexiSpace.s12,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(LexiRadius.md),
            border: Border.all(
              color: border,
              width: state == _OptionState.selected ? selectedBorderWidth : 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              // 判定结果额外给一个图标：颜色不能是唯一的信号
              // （HIG `accessibility.md`：不要只靠颜色传达信息）。
              if (_resultIcon case final icon?) ...<Widget>[
                Icon(icon, size: 18, color: foreground),
                const SizedBox(width: LexiSpace.s8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      label,
                      style: LexiType.callout.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (definition case final text?) ...<Widget>[
                      const SizedBox(height: LexiSpace.s2),
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
            ],
          ),
        ),
      ),
    );
  }

  /// 判定结果对应的图标；未判定时为 `null`。
  IconData? get _resultIcon => switch (state) {
    _OptionState.correct => Icons.check_circle_rounded,
    _OptionState.wrong => Icons.cancel_rounded,
    _ => null,
  };
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
