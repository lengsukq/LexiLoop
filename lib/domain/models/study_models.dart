/// 学习会话与每日队列的纯数据模型。
library;

import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';

/// 候选池的筛选范围。
enum CandidateScope {
  /// 只取单词与短语。
  lexical,

  /// 只取句子。
  sentence,

  /// 全部词条。
  all,
}

/// 一个可进入学习会话的候选词条。
class StudyCandidate {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    this.masteryScore,
    this.continuousTaskType,
    this.recommendedQuestionType,
  });

  /// 词条 ID。
  final int id;

  /// 展示用文本。
  final String term;

  /// 归一化文本。
  final String normalizedTerm;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 内容类型。
  final LexicalContentType contentType;

  /// 掌握分（可能为 `null`，表示从未复习过）。
  final int? masteryScore;

  /// 由连续学习（`continuousCandidates`）判定的任务类型。
  final StudyTaskType? continuousTaskType;

  /// AI 推荐指定的题型。
  final QuestionType? recommendedQuestionType;

  /// 复制并覆盖任务类型。
  StudyCandidate withTaskType(StudyTaskType taskType) => StudyCandidate(
    id: id,
    term: term,
    normalizedTerm: normalizedTerm,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    contentType: contentType,
    masteryScore: masteryScore,
    continuousTaskType: taskType,
    recommendedQuestionType: recommendedQuestionType,
  );
}

/// 各候选池的配额。
class PoolLimits {
  /// 以各字段构造。
  const new({required this.due, required this.wrong, required this.fresh});

  /// 到期复习配额。
  final int due;

  /// 错词配额。
  final int wrong;

  /// 新词配额。
  final int fresh;
}

/// 三个候选池及其配额。
class StudyPools {
  /// 以各字段构造。
  const new({
    required this.due,
    required this.wrong,
    required this.fresh,
    required this.limits,
  });

  /// 到期复习候选。
  final List<StudyCandidate> due;

  /// 错词候选。
  final List<StudyCandidate> wrong;

  /// 新词候选。
  final List<StudyCandidate> fresh;

  /// 各池配额。
  final PoolLimits limits;

  /// 三个池的候选总数。
  int get length => due.length + wrong.length + fresh.length;
}

/// 可用候选数量统计。
class CandidateAvailability {
  /// 以各字段构造。
  const new({required this.due, required this.wrong, required this.fresh});

  /// 到期复习数量。
  final int due;

  /// 错词数量。
  final int wrong;

  /// 新词数量。
  final int fresh;
}

/// 每日学习计划（首页展示用）。
class DailyStudyPlan {
  /// 以各字段构造。
  const new({
    required this.dueReviewCount,
    required this.plannedDueReviewCount,
    required this.wrongWordCount,
    required this.plannedWrongWordCount,
    required this.newWordCount,
    required this.plannedNewWordCount,
    required this.sentenceReviewCount,
    required this.plannedSentenceReviewCount,
    required this.plannedTotal,
    required this.activeSessionTasks,
    required this.estimatedMinutes,
  });

  /// 当前可复习的到期卡数量。
  final int dueReviewCount;

  /// 本次计划纳入的到期复习数。
  final int plannedDueReviewCount;

  /// 当前错词本数量。
  final int wrongWordCount;

  /// 本次计划纳入的错词数。
  final int plannedWrongWordCount;

  /// 当前待学新词数量。
  final int newWordCount;

  /// 本次计划纳入的新词数。
  final int plannedNewWordCount;

  /// 当前可复习的句子数量。
  final int sentenceReviewCount;

  /// 本次计划纳入的句子数。
  final int plannedSentenceReviewCount;

  /// 计划总题数（含未完成的活跃会话）。
  final int plannedTotal;

  /// 未完成会话中已存在的题目数。
  final int activeSessionTasks;

  /// 预估耗时（分钟）。
  final int estimatedMinutes;
}

/// 一道题的选项集合。
class QuestionChoices {
  /// 以各字段构造。
  const new({required this.choices, required this.choiceDefinitions});

  /// 选项文本（已打乱）。
  final List<String> choices;

  /// 「看汉选英」题中每个英文选项对应的中文释义。
  final Map<String, String> choiceDefinitions;
}

/// 填空题的附加信息。
class ClozePayload {
  /// 以各字段构造。
  const new({
    required this.sentence,
    required this.blankedSentence,
    this.translation,
  });

  /// 原句。
  final String sentence;

  /// 挖空后的句子。
  final String blankedSentence;

  /// 原句翻译。
  final String? translation;
}

/// 字母拼图的一块。
class LetterTile {
  /// 以各字段构造。
  const new({required this.id, required this.value});

  /// 稳定的块 ID（同一字母的不同位置必须可区分）。
  final String id;

  /// 字母。
  final String value;
}

/// 一条发音信息。
class PronunciationView {
  /// 以各字段构造。
  const new({
    required this.accent,
    required this.phonetic,
    this.audioUrl,
    this.source,
  });

  /// 口音。
  final Accent accent;

  /// 音标。
  final String phonetic;

  /// 音频地址（词典提供时）。
  final String? audioUrl;

  /// 提供这条发音的数据源标识（如 `youdao`、`merriam-webster`）。
  ///
  /// **为什么必须有它**：旧版详情页判断「是否优先播放有道真人发音」靠的是
  /// `pronunciations[].source === "youdao"`，若这一列不落到视图模型上，
  /// 新版就只能从 URL 形状反推来源——那既不可靠也不可读。
  final String? source;
}

/// 一条例句。
class ExampleView {
  /// 以各字段构造。
  const new({
    required this.sentence,
    this.translation,
    this.senseId,
    this.difficulty,
  });

  /// 例句原文。
  final String sentence;

  /// 例句翻译。
  final String? translation;

  /// 本例句演示的义项编号，指向 `DefinitionValue.senseId`。
  final String? senseId;

  /// 难度分级（真实备份里取值 `EASY` / `NORMAL` / `ADVANCED`）。
  ///
  /// 只有 AI 渠道的例句带这个字段，词典例句为 `null`；按原始文本透传，
  /// 不在本层做映射——未知取值不该被静默折叠成同一档。
  final String? difficulty;
}

/// 学习界面需要的词条视图。
///
/// 只带学习与朗读必需的字段：详情页要用的词根、词族、易混词等
/// 不在这里加载，避免一次会话把整张 `word_contents` 拖进内存。
class StudyWordView {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    required this.definitions,
    required this.pronunciations,
    required this.examples,
    this.translation,
  });

  /// 词条 ID。
  final int id;

  /// 展示用文本。
  final String term;

  /// 源语言代码。
  final String sourceLanguage;

  /// 目标语言代码。
  final String targetLanguage;

  /// 内容类型。
  final LexicalContentType contentType;

  /// 释义（已解析、已过滤空文本）。
  final List<DefinitionValue> definitions;

  /// 发音列表。
  final List<PronunciationView> pronunciations;

  /// 例句列表。
  final List<ExampleView> examples;

  /// 句子类词条的整句翻译（`summary.translation`）。
  final String? translation;

  /// 是否至少有一条带句子的例句——决定能否出填空题。
  bool get hasExample =>
      examples.any((item) => item.sentence.trim().isNotEmpty);
}

/// 一道题的完整视图。
class StudyItemView {
  /// 以各字段构造。
  const new({
    required this.itemId,
    required this.position,
    required this.taskType,
    required this.questionType,
    required this.status,
    required this.word,
    this.skipReason,
    this.choices = const <String>[],
    this.choiceDefinitions = const <String, String>{},
    this.cloze,
    this.letters = const <LetterTile>[],
  });

  /// 题目 ID。
  final int itemId;

  /// 在会话中的位置（升序）。
  final double position;

  /// 任务类型。
  final StudyTaskType taskType;

  /// 题型。
  final QuestionType questionType;

  /// 作答状态。
  final StudyItemStatus status;

  /// 跳过原因。
  final String? skipReason;

  /// 词条视图。
  final StudyWordView word;

  /// 选项文本（选择题）。
  final List<String> choices;

  /// 「看汉选英」题中英文选项 → 中文释义。
  final Map<String, String> choiceDefinitions;

  /// 填空题载荷。
  final ClozePayload? cloze;

  /// 字母拼图块。
  final List<LetterTile> letters;
}

/// 一次学习会话的完整视图。
class StudySessionView {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.mode,
    required this.startedAt,
    required this.plannedCount,
    required this.completedCount,
    required this.correctCount,
    required this.wrongCount,
    required this.skippedCount,
    required this.items,
    required this.resumeIndex,
    required this.resumed,
    this.sourceType,
    this.completedAt,
    this.durationMs,
  });

  /// 会话 ID。
  final int id;

  /// 学习模式。
  final StudyMode mode;

  /// 特殊来源（`AI_RECOMMENDED` / `SENTENCE_REVIEW`）。
  final String? sourceType;

  /// 开始时间（epoch 毫秒）。
  final int startedAt;

  /// 完成时间。
  final int? completedAt;

  /// 计划题数。
  final int plannedCount;

  /// 已作答题数。
  final int completedCount;

  /// 答对题数。
  final int correctCount;

  /// 答错题数。
  final int wrongCount;

  /// 跳过题数。
  final int skippedCount;

  /// 有效学习时长。
  final int? durationMs;

  /// 全部题目（按位置升序）。
  final List<StudyItemView> items;

  /// 第一道待答题目的下标；全部答完时等于 `items.length`。
  final int resumeIndex;

  /// 本次是否为恢复既有会话。
  final bool resumed;

  /// 是否已全部作答。
  bool get isFinished => resumeIndex >= items.length;

  /// 当前待作答的题目；已结束时为 `null`。
  StudyItemView? get currentItem => isFinished ? null : items[resumeIndex];
}
