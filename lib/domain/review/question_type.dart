/// 题型选择。
///
/// 对应旧版 `modules/study/question-type-config.ts` 与 `study/candidates.ts`
/// 的 `questionFor` / `taskFor`。
///
/// 随机源通过 [QuestionTypeRandom] 注入而不是直接用 `Random()`，
/// 使「在给定随机序列下选出哪个题型」可被确定性断言。
library;

import 'dart:math' as math;

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/app_settings.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 可注入的随机源，返回 `[0, 1)` 区间的值。
typedef QuestionTypeRandom = double Function();

/// 题型选择所需的词条附加信息。
class QuestionTypeContext {
  /// 以各字段构造。
  const new({this.term, this.hasExample = false});

  /// 词条文本（用于判断是否适合字母拼图）。
  final String? term;

  /// 是否至少有一条带句子的例句（用于判断是否可出填空题）。
  final bool hasExample;
}

/// 题型在当前词条上是否可用。
bool isQuestionTypeEligible(QuestionType type, QuestionTypeContext context) {
  if (type == QuestionType.clozeSentence && !context.hasExample) return false;
  if (type == QuestionType.letterBank &&
      !_isSimpleSpellingTerm(context.term ?? '')) {
    return false;
  }
  return true;
}

/// 各回退池。
///
/// 抽成命名常量而不是内联字面量，一是让 `modeFallbackPool` 保持在一屏内，
/// 二是这些池子本身就是「教学设计」的一部分，值得被单独审阅。
const List<QuestionType> listeningFallbackPool = <QuestionType>[
  QuestionType.listeningSpelling,
  QuestionType.listeningChoice,
];

/// 拼写类学习的回退池。
const List<QuestionType> spellingFallbackPool = <QuestionType>[
  QuestionType.zhToEnSpelling,
  QuestionType.letterBank,
];

/// 句子复习中「新句」的回退池。
const List<QuestionType> sentenceNewFallbackPool = <QuestionType>[
  QuestionType.enToZh,
];

/// 句子复习中「复习」的回退池。
const List<QuestionType> sentenceReviewFallbackPool = <QuestionType>[
  QuestionType.zhToEnSpelling,
  QuestionType.enToZh,
];

/// 到期复习与新词学习的回退池。
const List<QuestionType> reviewFallbackPool = <QuestionType>[
  QuestionType.enToZhChoice,
  QuestionType.enToZh,
];

/// 全局兜底池，覆盖全部 8 种题型。
const List<QuestionType> globalFallbackPool = <QuestionType>[
  QuestionType.enToZhChoice,
  QuestionType.zhToEnChoice,
  QuestionType.zhToEnSpelling,
  QuestionType.enToZh,
  QuestionType.listeningChoice,
  QuestionType.listeningSpelling,
  QuestionType.clozeSentence,
  QuestionType.letterBank,
];

/// 追问时围绕「拼写类」递进的池子。
const List<QuestionType> adaptiveSpellingPool = <QuestionType>[
  QuestionType.zhToEnSpelling,
  QuestionType.enToZhChoice,
  QuestionType.zhToEnChoice,
  QuestionType.letterBank,
  QuestionType.clozeSentence,
  QuestionType.enToZh,
];

/// 追问时围绕「听力类」递进的池子。
const List<QuestionType> adaptiveListeningPool = <QuestionType>[
  QuestionType.listeningSpelling,
  QuestionType.listeningChoice,
];

/// 首选题型不可用时，按学习模式回退的池子。
List<QuestionType> modeFallbackPool(StudyMode mode, StudyTaskType taskType) {
  if (taskType == StudyTaskType.wrong) return spellingFallbackPool;
  return switch (mode) {
    StudyMode.listening => listeningFallbackPool,
    StudyMode.spelling || StudyMode.wrongWords => spellingFallbackPool,
    StudyMode.sentenceReview =>
      taskType == StudyTaskType.newWord
          ? sentenceNewFallbackPool
          : sentenceReviewFallbackPool,
    StudyMode.dueReview || StudyMode.newWords => reviewFallbackPool,
    StudyMode.daily || StudyMode.aiRecommended => globalFallbackPool,
  };
}

/// 按权重从池中抽一个可用题型；池内无可用项时返回 `null`。
QuestionType? weightedPickFromPool(
  List<QuestionType> pool,
  QuestionTypeContext context,
  QuestionTypeConfig config,
  QuestionTypeRandom random,
) {
  final eligible = pool
      .where(
        (type) =>
            config.isEnabled(type) && isQuestionTypeEligible(type, context),
      )
      .toList(growable: false);
  if (eligible.isEmpty) return null;
  if (eligible.length == 1) return eligible.first;

  final weights = eligible
      .map((type) => math.max(questionTypeWeightFloor, config.weightOf(type)))
      .toList(growable: false);
  final total = weights.reduce((sum, weight) => sum + weight);

  var cursor = _boundedRandom(random) * total;
  for (var index = 0; index < eligible.length; index += 1) {
    cursor -= weights[index];
    if (cursor < 0) return eligible[index];
  }
  return eligible.last;
}

/// 解析最终题型：首选可用则用首选，否则按模式回退，再不行全局兜底。
QuestionType resolveQuestionType({
  required QuestionType preferred,
  required StudyMode mode,
  required StudyTaskType taskType,
  required QuestionTypeContext context,
  required QuestionTypeConfig config,
  QuestionTypeRandom? random,
}) {
  final source = random ?? _defaultRandom;
  if (config.isEnabled(preferred) &&
      isQuestionTypeEligible(preferred, context)) {
    return preferred;
  }
  final picked = weightedPickFromPool(
    modeFallbackPool(mode, taskType),
    context,
    config,
    source,
  );
  if (picked != null) return picked;
  return weightedPickFromPool(globalFallbackPool, context, config, source) ??
      QuestionType.enToZhChoice;
}

/// 追问（自适应插题）时的题型解析：池子只围绕当前题型做难度递进。
QuestionType resolveAdaptiveQuestionType({
  required QuestionType preferred,
  required QuestionTypeContext context,
  required QuestionTypeConfig config,
  QuestionTypeRandom? random,
}) {
  final source = random ?? _defaultRandom;
  if (config.isEnabled(preferred) &&
      isQuestionTypeEligible(preferred, context)) {
    return preferred;
  }
  final pool =
      preferred == QuestionType.listeningSpelling ||
          preferred == QuestionType.listeningChoice
      ? const <QuestionType>[
          QuestionType.listeningSpelling,
          QuestionType.listeningChoice,
        ]
      : const <QuestionType>[
          QuestionType.zhToEnSpelling,
          QuestionType.enToZhChoice,
          QuestionType.zhToEnChoice,
          QuestionType.letterBank,
          QuestionType.clozeSentence,
          QuestionType.enToZh,
        ];
  return weightedPickFromPool(pool, context, config, source) ??
      QuestionType.zhToEnSpelling;
}

/// 按模式与作答位置挑选题型。
///
/// `position` 参与取模是为了让同一会话内题型**交替出现**——连续 10 道
/// 选择题会让用户进入机械作答状态，失去检索练习的意义。
QuestionType questionFor({
  required StudyMode mode,
  required StudyTaskType taskType,
  required QuestionTypeContext context,
  required QuestionTypeConfig config,
  int position = 0,
  int? masteryScore,
  QuestionTypeRandom? random,
}) {
  QuestionType pick(QuestionType preferred) => resolveQuestionType(
    preferred: preferred,
    mode: mode,
    taskType: taskType,
    context: context,
    config: config,
    random: random,
  );

  switch (mode) {
    case StudyMode.sentenceReview:
      return pick(
        taskType == StudyTaskType.newWord
            ? QuestionType.enToZh
            : QuestionType.zhToEnSpelling,
      );
    case StudyMode.listening:
      if (position % listeningWeakMasteryEvery == listeningWeakMasteryOffset &&
          masteryScore != null &&
          masteryScore < listeningWeakMasteryScore) {
        return pick(QuestionType.listeningChoice);
      }
      // listeningChoiceEvery 为 2，等价于「奇数位置出选择题」。
      if (position.isOdd) {
        return pick(QuestionType.listeningChoice);
      }
      return pick(QuestionType.listeningSpelling);
    case StudyMode.spelling:
    case StudyMode.wrongWords:
      return _spellingQuestion(pick, context, position);
    case StudyMode.daily:
    case StudyMode.aiRecommended:
      return _dailyQuestion(pick, taskType, context, position, masteryScore);
    case StudyMode.dueReview:
    case StudyMode.newWords:
      return pick(QuestionType.enToZhChoice);
  }
}

/// 判定候选词条的任务类型。
StudyTaskType taskFor({
  required StudyMode mode,
  required StudyCandidate candidate,
  required Set<int> dueIds,
  required Set<int> wrongIds,
}) {
  switch (mode) {
    case StudyMode.listening:
      return StudyTaskType.listening;
    case StudyMode.spelling:
      return StudyTaskType.spelling;
    case StudyMode.dueReview:
      return StudyTaskType.review;
    case StudyMode.newWords:
      return StudyTaskType.newWord;
    case StudyMode.daily:
    case StudyMode.wrongWords:
    case StudyMode.sentenceReview:
    case StudyMode.aiRecommended:
      break;
  }
  final continuous = candidate.continuousTaskType;
  if (continuous != null) return continuous;
  if (dueIds.contains(candidate.id)) return StudyTaskType.review;
  if (wrongIds.contains(candidate.id)) return StudyTaskType.wrong;
  return StudyTaskType.newWord;
}

QuestionType _spellingQuestion(
  QuestionType Function(QuestionType) pick,
  QuestionTypeContext context,
  int position,
) {
  final term = context.term;
  if (term != null &&
      _isSimpleSpellingTerm(term) &&
      position % spellingLetterBankEvery == 0) {
    return pick(QuestionType.letterBank);
  }
  return pick(QuestionType.zhToEnSpelling);
}

QuestionType _dailyQuestion(
  QuestionType Function(QuestionType) pick,
  StudyTaskType taskType,
  QuestionTypeContext context,
  int position,
  int? masteryScore,
) {
  if (taskType == StudyTaskType.newWord) return pick(QuestionType.enToZh);

  final term = context.term ?? '';
  if (masteryScore != null) {
    if (masteryScore < dailyLowMasteryScore) {
      return pick(QuestionType.enToZhChoice);
    }
    if (masteryScore < dailyMediumMasteryScore && context.hasExample) {
      return pick(QuestionType.clozeSentence);
    }
    if (masteryScore < dailyHighMasteryScore) {
      return pick(QuestionType.zhToEnChoice);
    }
    if (_isSimpleSpellingTerm(term) && position % dailyLetterBankEvery == 0) {
      return pick(QuestionType.letterBank);
    }
    return pick(QuestionType.zhToEnSpelling);
  }
  if (position % dailyClozeEvery == dailyClozeOffset && context.hasExample) {
    return pick(QuestionType.clozeSentence);
  }
  if (position % dailyLetterBankEvery == dailyLetterBankOffset &&
      _isSimpleSpellingTerm(term)) {
    return pick(QuestionType.letterBank);
  }
  return pick(
    position.isOdd ? QuestionType.zhToEnChoice : QuestionType.enToZhChoice,
  );
}

bool _isSimpleSpellingTerm(String term) =>
    RegExp(letterBankTermPattern).hasMatch(term);

double _boundedRandom(QuestionTypeRandom random) =>
    math.min(questionTypeRandomCeiling, math.max(0, random()));

final double Function() _defaultRandom = math.Random().nextDouble;
