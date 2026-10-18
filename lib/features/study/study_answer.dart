/// 作答区入口：按题型分发到具体输入组件。
///
/// 本文件只做**分发**；每个题型的输入控件在自己的文件里，避免一个文件里
/// 塞进四种互不相干的交互（旧版 `study-client.tsx` 497 行的直接教训）。
///
/// **揭示后卸载输入控件**：答案已经进入揭示面板，留着灰掉的输入框/字母盘
/// 只会把判定挤到折叠线以下。选择题是例外——正确项与错选项的标记本身就是
/// 反馈，需要继续显示。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/answer_evaluator.dart';
import 'package:lexiloop/features/study/study_choice_options.dart';
import 'package:lexiloop/features/study/study_letter_bank.dart';
import 'package:lexiloop/features/study/study_text_answer.dart';

/// 作答区：把当前题型的输入控件组装起来。
class StudyAnswerArea extends StatelessWidget {
  /// 以题目、当前作答、是否已揭示与两个回调构造。
  const new({
    required this.item,
    required this.answer,
    required this.revealed,
    required this.onAnswer,
    required this.onCheck,
    super.key,
  });

  /// 当前题目。
  final StudyItemView item;

  /// 当前作答文本（选择题是选中项，字母拼词是拼出的字符串）。
  final String answer;

  /// 是否已经揭示答案。
  final bool revealed;

  /// 作答内容变化时回调。
  final ValueChanged<String> onAnswer;

  /// 文本题回车检查时回调。
  final VoidCallback onCheck;

  @override
  Widget build(BuildContext context) {
    if (choiceQuestionTypes.contains(item.questionType)) {
      return ChoiceOptions(
        key: ValueKey<int>(item.itemId),
        item: item,
        selected: answer.isEmpty ? null : answer,
        revealed: revealed,
        onSelect: onAnswer,
      );
    }
    // 看词说义没有输入控件：先「显示答案」，再用自评表达记得程度。
    if (item.questionType == QuestionType.enToZh) {
      return const SizedBox.shrink();
    }
    if (revealed) return const SizedBox.shrink();
    return switch (item.questionType) {
      QuestionType.zhToEnSpelling ||
      QuestionType.listeningSpelling ||
      QuestionType.clozeSentence => TextAnswerField(
        key: ValueKey<int>(item.itemId),
        item: item,
        onAnswer: onAnswer,
        onCheck: onCheck,
      ),
      QuestionType.letterBank => LetterBank(
        key: ValueKey<int>(item.itemId),
        item: item,
        onAnswer: onAnswer,
      ),
      _ => const SizedBox.shrink(),
    };
  }
}
