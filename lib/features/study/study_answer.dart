/// 作答区入口：按题型分发到具体输入组件。
///
/// 本文件只做**分发**与提交按钮；每个题型的输入控件在自己的文件里，
/// 避免一个文件里塞进四种互不相干的交互（旧版 `study-client.tsx` 497 行的
/// 直接教训）。
library;

import 'package:flutter/material.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/features/study/study_choice_options.dart';
import 'package:lexiloop/features/study/study_letter_bank.dart';
import 'package:lexiloop/features/study/study_text_answer.dart';

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
