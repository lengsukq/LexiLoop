/// 客观判题。
///
/// 对应旧版 `modules/reviews/answer-evaluation.ts`。
///
/// **与旧版的差异（有意）**：旧版在 `spelling` 分支之后又写了
/// `if (CLOZE_SENTENCE)` 与 `if (LETTER_BANK)` 两个分支，但这两个题型
/// 已经包含在 `spelling` 里，那两段是不可达代码。此处不再复制。
library;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/review_models.dart';
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

/// 判题并推导实际生效的等级。
AnswerEvaluation evaluateAnswer(AnswerInput input, ReviewWord word) {
  final definitions = targetDefinitions(
    parseDefinitionsJson(word.definitionsJson),
    word.targetLanguage,
  );
  final isCorrect = _isAnswerCorrect(input, word, definitions);
  return AnswerEvaluation(
    isCorrect: isCorrect,
    effectiveRating: _effectiveRating(input, isCorrect),
    expectedAnswer: _expectedAnswer(input.questionType, word, definitions),
    presentedPrompt: _presentedPrompt(input.questionType, word, definitions),
  );
}

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

bool _isAnswerCorrect(
  AnswerInput input,
  ReviewWord word,
  List<DefinitionValue> definitions,
) {
  final userAnswer = input.userAnswer ?? '';

  if (textAnswerQuestionTypes.contains(input.questionType)) {
    return _isTextAnswerCorrect(userAnswer, word);
  }
  if (input.questionType == QuestionType.enToZhChoice) {
    return _isMeaningChoiceCorrect(userAnswer, definitions, input.rating);
  }
  if (input.questionType == QuestionType.zhToEnChoice ||
      input.questionType == QuestionType.listeningChoice) {
    return _matchesTerm(userAnswer, word);
  }
  // 无客观依据的题型（如 EN_TO_ZH 自由作答）只能采信自评。
  return input.rating != ReviewRating.again;
}

bool _isTextAnswerCorrect(String userAnswer, ReviewWord word) {
  if (word.contentType == LexicalContentType.sentence) {
    return _isSentenceAnswerCorrect(userAnswer, word.term);
  }
  return _matchesTerm(userAnswer, word);
}

bool _isSentenceAnswerCorrect(String userAnswer, String expected) {
  final userNorm = normalizeSentenceAnswer(userAnswer);
  final expectedNorm = normalizeSentenceAnswer(expected);
  if (userNorm == expectedNorm) return true;
  if (expectedNorm.length <= sentenceFuzzyMinLength) return false;
  return levenshteinDistance(userNorm, expectedNorm) <=
      sentenceFuzzyTolerance(expectedNorm.length);
}

bool _matchesTerm(String userAnswer, ReviewWord word) {
  final userTerm = normalizeTerm(userAnswer, word.sourceLanguage);
  final targetTerm = word.normalizedTerm;
  if (userTerm == targetTerm) return true;
  if (canonicalTerm(userTerm) == canonicalTerm(targetTerm)) return true;
  return isSingleTypoOf(userTerm, targetTerm);
}

bool _isMeaningChoiceCorrect(
  String userAnswer,
  List<DefinitionValue> definitions,
  ReviewRating rating,
) {
  final correct = definitions
      .map((definition) => definition.text.trim())
      .where((text) => text.isNotEmpty)
      .toList(growable: false);
  if (correct.isEmpty) return rating != ReviewRating.again;

  final answer = userAnswer.trim();
  // 选项可能是合并后的整串（「释义一；释义二」），也可能是单条释义。
  if (answer == correct.join(definitionSeparator)) return true;
  return correct.contains(answer);
}

/// 定义题问「这个词是什么意思」，其余题问「这个意思是什么词」。
bool _isDefinitionQuestion(QuestionType type) =>
    type == QuestionType.enToZh || type == QuestionType.enToZhChoice;

String _expectedAnswer(
  QuestionType type,
  ReviewWord word,
  List<DefinitionValue> definitions,
) => _isDefinitionQuestion(type)
    ? definitions.map((definition) => definition.text).join(definitionSeparator)
    : word.term;

String _presentedPrompt(
  QuestionType type,
  ReviewWord word,
  List<DefinitionValue> definitions,
) => _isDefinitionQuestion(type)
    ? word.term
    : definitions
          .map((definition) => definition.text)
          .join(definitionSeparator);
