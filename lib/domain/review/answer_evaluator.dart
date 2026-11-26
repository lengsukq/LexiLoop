/// 客观判题。
///
/// 对应旧版 `modules/reviews/answer-evaluation.ts`。
///
/// **与旧版的差异（有意）**：旧版在 `spelling` 分支之后又写了
/// `if (CLOZE_SENTENCE)` 与 `if (LETTER_BANK)` 两个分支，但这两个题型
/// 已经包含在 `spelling` 里，那两段是不可达代码。此处不再复制。
///
/// **界面预览与写库判题共用同一套函数**：学习页要在自评**之前**把对错、
/// 正确答案显示出来（见 `features/study/study_reveal.dart`），但界面不能
/// 自己再判一遍——本地判错、服务判对会让「揭示说错、库里记对」无从解释。
/// [previewAnswer] 与 [evaluateAnswer] 因此走同一个 [_answerCorrectness]。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
import 'package:lexiloop/domain/models/study_models.dart';
import 'package:lexiloop/domain/review/spelling.dart';
import 'package:lexiloop/domain/text/normalizer.dart';

/// 需要用户**输入文本**、可被客观判分的题型。
const Set<QuestionType> textAnswerQuestionTypes = <QuestionType>{
  QuestionType.zhToEnSpelling,
  QuestionType.listeningSpelling,
  QuestionType.clozeSentence,
  QuestionType.letterBank,
};

/// 可从选项中客观判分的题型。
const Set<QuestionType> choiceQuestionTypes = <QuestionType>{
  QuestionType.enToZhChoice,
  QuestionType.zhToEnChoice,
  QuestionType.listeningChoice,
};

/// 题型是否可被客观判分。
///
/// 主观题（看英选中、听音拼写以外的自由作答）只能采信用户自评。
bool isObjectivelyScored(QuestionType type) =>
    textAnswerQuestionTypes.contains(type) ||
    choiceQuestionTypes.contains(type);

/// 作答的本地预览：只读、不写库、不推进 FSRS。
///
/// 学习页在「揭示答案」时用它显示对错与正确答案；自评提交后仍以
/// 服务层返回的 `ReviewOutcome` 为准。两者判题函数相同，因此结论一致。
class AnswerPreview {
  /// 以正误与期望答案构造。
  const new({required this.isCorrect, required this.expectedAnswer});

  /// 客观判定结果；主观题（看词说义）为 `null`。
  ///
  /// `null` 不是「判错」：看词说义没有可比的答案，界面应显示「参考答案」
  /// 而不是一个绿勾或红叉。
  final bool? isCorrect;

  /// 期望答案。
  final String expectedAnswer;
}

/// 判题所需的最小事实集合。
///
/// 服务层从数据库行构造，界面层从 [StudyWordView] 构造；[definitions] 已经
/// 按目标语言过滤（与写库路径完全相同的那一步）。
class _AnswerTarget {
  const new({
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    required this.definitions,
  });

  /// 从数据库判题行构造。
  factory _ofWord(ReviewWord word) => _AnswerTarget(
    term: word.term,
    normalizedTerm: word.normalizedTerm,
    sourceLanguage: word.sourceLanguage,
    targetLanguage: word.targetLanguage,
    contentType: word.contentType,
    definitions: targetDefinitions(
      parseDefinitionsJson(word.definitionsJson),
      word.targetLanguage,
    ),
  );

  /// 从学习页词条视图构造。
  ///
  /// `normalizedTerm` 走与入库同一个 [normalizeTerm]：两处不一致会制造
  /// 「能导入但判错」的幽灵 bug，这里不能各算各的。
  factory _ofView(StudyWordView word) => _AnswerTarget(
    term: word.term,
    normalizedTerm: normalizeTerm(word.term, word.sourceLanguage),
    sourceLanguage: word.sourceLanguage,
    targetLanguage: word.targetLanguage,
    contentType: word.contentType,
    definitions: targetDefinitions(word.definitions, word.targetLanguage),
  );

  final String term;
  final String normalizedTerm;
  final String sourceLanguage;
  final String targetLanguage;
  final LexicalContentType contentType;
  final List<DefinitionValue> definitions;
}

/// 判题并推导实际生效的等级。
AnswerEvaluation evaluateAnswer(AnswerInput input, ReviewWord word) {
  final target = _AnswerTarget._ofWord(word);
  final correctness = _answerCorrectness(
    input.questionType,
    target,
    input.userAnswer ?? '',
  );
  final isCorrect = _isCorrect(correctness, input.rating);
  return AnswerEvaluation(
    isCorrect: isCorrect,
    effectiveRating: _effectiveRating(input, isCorrect),
    expectedAnswer: _expectedAnswer(input.questionType, target),
    presentedPrompt: _presentedPrompt(input.questionType, target),
  );
}

/// 界面用的只读判题预览。
///
/// 与 [evaluateAnswer] 同一套判题函数：客观题给出 `true/false`，主观题
/// 给出 `null`（界面显示「参考答案」）。
AnswerPreview previewAnswer({
  required QuestionType questionType,
  required StudyWordView word,
  required String answer,
}) {
  final target = _AnswerTarget._ofView(word);
  return AnswerPreview(
    isCorrect: _answerCorrectness(questionType, target, answer),
    expectedAnswer: _expectedAnswer(questionType, target),
  );
}

/// 主观题的最终正误由自评决定：选「忘了」即判错，其余按对。
bool _isCorrect(bool? correctness, ReviewRating rating) =>
    correctness ?? rating != ReviewRating.again;

/// 客观题答错时降级为 AGAIN。
///
/// 两个例外体现「用户的主观判断优先于机械判分」：
/// - 选了「简单」：其实会，只是点错了选项；
/// - 选了「模糊」：记得但不确定，不算完全遗忘。
///
/// 「模糊」同时意味着不进当前会话的重插队列（见 `study/adaptive`）。
ReviewRating _effectiveRating(AnswerInput input, bool isCorrect) {
  final objective = isObjectivelyScored(input.questionType);
  if (!objective || isCorrect) return input.rating;
  if (input.rating == ReviewRating.easy || input.rating == ReviewRating.hard) {
    return input.rating;
  }
  return ReviewRating.again;
}

/// 客观正误；主观题或无法客观判定时返回 `null`。
bool? _answerCorrectness(
  QuestionType type,
  _AnswerTarget target,
  String userAnswer,
) {
  if (textAnswerQuestionTypes.contains(type)) {
    return target.contentType == LexicalContentType.sentence
        ? _isSentenceAnswerCorrect(userAnswer, target.term)
        : _matchesTerm(userAnswer, target);
  }
  if (type == QuestionType.enToZhChoice) {
    return _isMeaningChoiceCorrect(userAnswer, target.definitions);
  }
  if (type == QuestionType.zhToEnChoice ||
      type == QuestionType.listeningChoice) {
    return _matchesTerm(userAnswer, target);
  }
  // 无客观依据的题型（如 EN_TO_ZH 自由作答）只能采信自评。
  return null;
}

bool _isSentenceAnswerCorrect(String userAnswer, String expected) {
  final userNorm = normalizeSentenceAnswer(userAnswer);
  final expectedNorm = normalizeSentenceAnswer(expected);
  if (userNorm == expectedNorm) return true;
  if (expectedNorm.length <= sentenceFuzzyMinLength) return false;
  return levenshteinDistance(userNorm, expectedNorm) <=
      sentenceFuzzyTolerance(expectedNorm.length);
}

bool _matchesTerm(String userAnswer, _AnswerTarget target) {
  final userTerm = normalizeTerm(userAnswer, target.sourceLanguage);
  final targetTerm = target.normalizedTerm;
  if (userTerm == targetTerm) return true;
  if (canonicalTerm(userTerm) == canonicalTerm(targetTerm)) return true;
  return isSingleTypoOf(userTerm, targetTerm);
}

/// 释义选项的判定；无可比释义时返回 `null`，由调用方退回自评。
bool? _isMeaningChoiceCorrect(
  String userAnswer,
  List<DefinitionValue> definitions,
) {
  final correct = definitions
      .map((definition) => definition.text.trim())
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
  if (correct.isEmpty) return null;

  final answer = userAnswer.trim();
  // 选项可能是合并后的整串（「释义一；释义二」），也可能是单条释义。
  if (answer == correct.join(definitionSeparator)) return true;
  return correct.contains(answer);
}

/// 定义题问「这个词是什么意思」，其余题问「这个意思是什么词」。
bool _isDefinitionQuestion(QuestionType type) =>
    type == QuestionType.enToZh || type == QuestionType.enToZhChoice;

String _expectedAnswer(QuestionType type, _AnswerTarget target) =>
    _isDefinitionQuestion(type)
    ? target.definitions
          .map((definition) => definition.text)
          .join(definitionSeparator)
    : target.term;

String _presentedPrompt(QuestionType type, _AnswerTarget target) =>
    _isDefinitionQuestion(type)
    ? target.term
    : target.definitions
          .map((definition) => definition.text)
          .join(definitionSeparator);
