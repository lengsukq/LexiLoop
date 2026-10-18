/// 拼写与填空的文本输入。
///
/// 输入框自己持有 `TextEditingController`，由父组件用 `ValueKey(itemId)`
/// 控制生命周期：换题即换 key，草稿自动归零。
///
/// **只负责「写答案」与「敲门」**：判定、揭示与锁定都在学习页。揭示后本组件
/// 会被页面卸载，因此这里不再需要 `outcome` 或禁用态——那套「灰掉但还占位」
/// 的输入框只会把判定挤到折叠线以下。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 拼写 / 填空输入框。
class TextAnswerField extends StatefulWidget {
  /// 以题目、输入回调与检查回调构造。
  const new({
    required this.item,
    required this.onAnswer,
    required this.onCheck,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 输入变化时回调。
  final ValueChanged<String> onAnswer;

  /// 回车或「检查答案」时回调。
  final VoidCallback onCheck;

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
    return TextField(
      controller: _controller,
      textInputAction: TextInputAction.done,
      onChanged: widget.onAnswer,
      onSubmitted: (_) => widget.onCheck(),
      decoration: InputDecoration(hintText: _hint),
    );
  }

  String get _hint => widget.item.questionType == QuestionType.clozeSentence
      ? '填入缺失的词'
      : '输入英文拼写';
}
