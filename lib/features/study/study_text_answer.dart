/// 拼写与填空的文本输入。
///
/// 输入框自己持有 `TextEditingController`，由父组件用 `ValueKey(itemId)`
/// 控制生命周期：换题即换 key，草稿自动归零。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/ui/theme/lexi_colors.dart';

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
