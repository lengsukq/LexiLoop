/// 学习会话的作答区域。
///
/// 每个题型一个组件，各自**自己持有草稿状态**（选中项、输入文本、字母块），
/// 只把「当前作答原文」向上回调。这样切换题目时只要换 `ValueKey`，草稿
/// 自然归零，不需要在父组件里手写一堆 reset 分支。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

/// 作答区：把当前题型的输入控件组装起来。
class StudyAnswerArea extends StatelessWidget {
  /// 以题目、判定结果与两个回调构造。
  const new({
    required this.item,
    required this.outcome,
    required this.onAnswer,
    required this.onSubmit,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 已提交的判定结果；未提交时为 `null`。
  final ReviewOutcome? outcome;

  /// 作答内容变化时回调。
  final ValueChanged<String> onAnswer;

  /// 键盘回车提交时回调。
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return switch (item.questionType) {
      QuestionType.enToZhChoice ||
      QuestionType.zhToEnChoice ||
      QuestionType.listeningChoice => ChoiceOptions(
        key: ValueKey<int>(item.itemId),
        item: item,
        outcome: outcome,
        onAnswer: onAnswer,
      ),
      QuestionType.zhToEnSpelling ||
      QuestionType.listeningSpelling ||
      QuestionType.clozeSentence => TextAnswerField(
        key: ValueKey<int>(item.itemId),
        item: item,
        outcome: outcome,
        onAnswer: onAnswer,
        onSubmit: onSubmit,
      ),
      QuestionType.letterBank => LetterBank(
        key: ValueKey<int>(item.itemId),
        item: item,
        outcome: outcome,
        onAnswer: onAnswer,
      ),
      // 看词说义没有输入控件：四档自评本身就是作答。
      QuestionType.enToZh => const SizedBox.shrink(),
    };
  }
}

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
                style: TextStyle(
                  color: foreground,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (definition case final text?) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  text,
                  style: TextStyle(
                    color: colors.secondaryLabel,
                    fontSize: 12.5,
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

/// 拼写 / 填空输入框。
class TextAnswerField extends StatefulWidget {
  /// 以题目、判定结果与两个回调构造。
  const new({
    required this.item,
    required this.outcome,
    required this.onAnswer,
    required this.onSubmit,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 已提交的判定结果；未提交时为 `null`。
  final ReviewOutcome? outcome;

  /// 输入变化时回调。
  final ValueChanged<String> onAnswer;

  /// 回车提交时回调。
  final VoidCallback onSubmit;

  @override
  State<TextAnswerField> createState() => _TextAnswerFieldState();
}

class _TextAnswerFieldState extends State<TextAnswerField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = widget.outcome;
    return TextField(
      controller: _controller,
      enabled: outcome == null,
      textInputAction: TextInputAction.done,
      onChanged: widget.onAnswer,
      onSubmitted: outcome == null ? (_) => widget.onSubmit() : null,
      decoration: InputDecoration(
        hintText: _hint,
        suffixIcon: outcome == null
            ? null
            : Icon(
                outcome.isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: outcome.isCorrect
                    ? context.lexiColors.success
                    : context.lexiColors.danger,
              ),
      ),
    );
  }

  String get _hint => widget.item.questionType == QuestionType.clozeSentence
      ? '填入缺失的词'
      : '输入英文拼写';
}

/// 字母拼图。
class LetterBank extends StatefulWidget {
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

  /// 拼接结果变化时回调。
  final ValueChanged<String> onAnswer;

  @override
  State<LetterBank> createState() => _LetterBankState();
}

class _LetterBankState extends State<LetterBank> {
  /// 已选中的块，顺序即拼接顺序。
  ///
  /// 记 [LetterTile] 而不是字母文本：同一个词里可能出现重复字母
  /// （`apple` 有两个 `p`），只按文本记录会让「用过的块」无法区分。
  final List<LetterTile> _picked = <LetterTile>[];

  String get _spelled => _picked.map((tile) => tile.value).join();

  @override
  Widget build(BuildContext context) {
    final locked = widget.outcome != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _SpellingDisplay(text: _spelled),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final tile in widget.item.letters)
              if (!_isPicked(tile))
                _LetterTileButton(
                  tile: tile,
                  enabled: !locked,
                  onTap: () => _pick(tile),
                ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: <Widget>[
            _SmallAction(
              icon: Icons.backspace_rounded,
              label: '退格',
              enabled: !locked && _picked.isNotEmpty,
              onTap: _backspace,
            ),
            const SizedBox(width: 10),
            _SmallAction(
              icon: Icons.clear_rounded,
              label: '清空',
              enabled: !locked && _picked.isNotEmpty,
              onTap: _clear,
            ),
          ],
        ),
      ],
    );
  }

  bool _isPicked(LetterTile tile) => _picked.any((item) => item.id == tile.id);

  void _pick(LetterTile tile) {
    setState(() => _picked.add(tile));
    widget.onAnswer(_spelled);
  }

  void _backspace() {
    if (_picked.isEmpty) return;
    setState(_picked.removeLast);
    widget.onAnswer(_spelled);
  }

  void _clear() {
    setState(_picked.clear);
    widget.onAnswer(_spelled);
  }
}

/// 当前拼接结果的展示位。
class _SpellingDisplay extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Container(
      key: const Key('study.letterBank.spelling'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 56),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.fill,
        borderRadius: BorderRadius.circular(LexiRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Text(
        text.isEmpty ? '点击下方字母拼写' : text,
        style: TextStyle(
          color: text.isEmpty ? colors.tertiaryLabel : colors.label,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

/// 单个字母块。
class _LetterTileButton extends StatelessWidget {
  const new({required this.tile, required this.enabled, required this.onTap});

  final LetterTile tile;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lexiColors;
    return Material(
      color: colors.fill,
      borderRadius: BorderRadius.circular(LexiRadius.sm),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(LexiRadius.sm),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: Text(
            tile.value,
            style: TextStyle(
              color: enabled ? colors.label : colors.tertiaryLabel,
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 退格 / 清空这类小动作按钮。
class _SmallAction extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(icon, size: 16),
        label: Text(label),
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
      style: TextStyle(color: colors.secondaryLabel, fontSize: 13),
    );
  }
}

/// 确认按钮。
///
/// 未作答或已提交时禁用：旧版把「提交」和「下一题」做成同一个按钮，
/// 连点两次会把同一题算两遍。
class SubmitButton extends StatelessWidget {
  /// 以可用性、忙碌标志与回调构造。
  const new({
    required this.enabled,
    required this.busy,
    required this.onSubmit,
    super.key,
  });

  /// 是否可提交。
  final bool enabled;

  /// 是否正在提交。
  final bool busy;

  /// 提交回调。
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 50, minWidth: 120),
      child: FilledButton(
        onPressed: enabled && !busy ? onSubmit : null,
        child: Text(busy ? '提交中…' : '确认'),
      ),
    );
  }
}
