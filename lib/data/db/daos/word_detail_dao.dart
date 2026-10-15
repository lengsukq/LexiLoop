/// 词条详情的只读查询。
///
/// **为什么单独成文件**：详情页要读 `words` 的 15 列加 `word_contents` 的
/// 16 个 JSON 列，再叠加卡片状态、统计、错词状态、复习日志与数据源调用
/// 审计。旧版把这些查询散在 `use-word-detail.ts`（343 行、约 40 个字段、
/// 横跨 6 个领域）与组件里，同一份 JSON 解析写了两遍。这里把「取数」全部
/// 收在 DAO，页面组件只接收已经解析好的数据类。
///
/// **只读**：写操作（暂停、笔记、删除、手工释义、例句增删）一律走
/// `WordEditService`，避免在只读 DAO 里混入写路径。
library;

import 'package:drift/drift.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/date_key.dart';
import 'package:lexiloop/data/db/daos/word_dao.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/domain/dictionary/content_parse.dart';
import 'package:lexiloop/domain/dictionary/definitions.dart';
import 'package:lexiloop/domain/enums.dart';
import 'package:lexiloop/domain/models/study_models.dart';

/// 详情页「复习历史」默认展示的条数。
///
/// 详情页是一屏概览而非流水账；超过 20 条后用户关心的是趋势而不是逐条记录。
/// 该值属于界面展示口径，待 `lib/core/constants.dart` 增设界面小节时迁入。

// ═══════════════════════════════════════════════════════════════
// 视图数据类
// ═══════════════════════════════════════════════════════════════

/// 一条短语。
class PhraseView {
  /// 以各字段构造。
  const new({required this.phrase, this.translation, this.source});

  /// 短语文本。
  final String phrase;

  /// 短语翻译。
  final String? translation;

  /// 数据来源标识。
  final String? source;
}

/// 一条词形变化（复数、过去式、比较级等）。
class FormView {
  /// 以各字段构造。
  const new({required this.form, this.label, this.translation});

  /// 变化后的形态。
  final String form;

  /// 变化类型（如「过去式」）。
  final String? label;

  /// 该形态的释义。
  final String? translation;
}

/// 一个相关词条（同义词 / 反义词 / 词族 / 易混词共用）。
///
/// 四类关系的元素形态完全一致，共用同一数据类可避免四份几乎相同的解析与
/// 渲染代码——旧版 `dictionary/selection.ts` 的 summary / learning /
/// sentenceAnalysis 三分支结构相同，正是「表驱动」的反面教材。
class RelatedWordView {
  /// 以各字段构造。
  const new({
    required this.word,
    this.translation,
    this.partOfSpeech,
    this.relation,
    this.source,
    this.difference,
  });

  /// 词条文本。
  final String word;

  /// 释义。
  final String? translation;

  /// 词性。
  final String? partOfSpeech;

  /// 关系（如「近义」「易混」）。
  final String? relation;

  /// 数据来源标识。
  final String? source;

  /// 与当前词条的区别说明（仅易混词常见）。
  final String? difference;
}

/// 一个词根。
class RootView {
  /// 以各字段构造。
  const new({
    required this.root,
    required this.meaning,
    this.origin,
    this.source,
  });

  /// 词根文本。
  final String root;

  /// 词根含义。
  final String meaning;

  /// 语源（拉丁语、希腊语等）。
  final String? origin;

  /// 数据来源标识。
  final String? source;
}

/// 词缀类型。
enum AffixKind implements WireEnum {
  /// 前缀。
  prefix('PREFIX'),

  /// 后缀。
  suffix('SUFFIX');

  new(this.wire);

  @override
  final String wire;
}

/// 一个词缀。
class AffixView {
  /// 以各字段构造。
  const new({
    required this.value,
    required this.meaning,
    required this.kind,
    this.source,
  });

  /// 词缀文本（如 `un-`、`-tion`）。
  final String value;

  /// 词缀含义。
  final String meaning;

  /// 前缀还是后缀。
  final AffixKind kind;

  /// 数据来源标识。
  final String? source;
}

/// 词条摘要（`summary_json`）。
///
/// 四个字段都是可选的：初始化到一半的词条可能只有 `translation`。
class SummaryView {
  /// 以各字段构造。
  const new({
    this.shortDefinition,
    this.translation,
    this.cefrLevel,
    this.frequency,
  });

  /// 简短定义。
  final String? shortDefinition;

  /// 整句翻译（句子类词条）。
  final String? translation;

  /// CEFR 等级（A1–C2）。
  final String? cefrLevel;

  /// 词频描述。原始数据可能是数字或字符串，统一按文本展示。
  final String? frequency;

  /// 四个字段是否全为空。
  bool get isEmpty =>
      shortDefinition == null &&
      translation == null &&
      cefrLevel == null &&
      frequency == null;
}

/// 学习辅助信息（`learning_json`）。
class LearningView {
  /// 以各字段构造。
  const new({
    this.pronunciationTip,
    this.mnemonic,
    this.commonMistakes = const <String>[],
  });

  /// 发音提示。
  final String? pronunciationTip;

  /// 助记法。
  final String? mnemonic;

  /// 常见错误。
  final List<String> commonMistakes;

  /// 三个字段是否全为空。
  bool get isEmpty =>
      pronunciationTip == null && mnemonic == null && commonMistakes.isEmpty;
}

/// 句子分析里的一条条目（关键表达 / 相似例句 / 句式变换共用）。
///
/// 三类条目的 JSON 键名不同（`expression` / `sentence`），正文都能落到
/// [text]；其余字段按各自的键单独保留，因为它们承载的是**不同的信息**：
/// 关键表达的 `meaning` 是中文对释、`note` 是搭配提示，相似例句的
/// `focus` 是「这条例句想演示什么」。把它们塞进同一个 `translation` 会让
/// 界面只能说「有则显示」，说不清那行字到底在讲什么。
class SentenceAnalysisItem {
  /// 以各字段构造。
  const new({
    required this.text,
    this.label,
    this.translation,
    this.meaning,
    this.note,
    this.focus,
  });

  /// 条目正文。
  final String text;

  /// 条目标签（如句式变换的类型）。
  final String? label;

  /// 条目翻译或说明。
  final String? translation;

  /// 关键表达的中文含义（`meaning`）。
  final String? meaning;

  /// 关键表达的使用提示（`note`）。
  final String? note;

  /// 相似例句的讲解重点（`focus`）。
  final String? focus;
}

/// 句子分析（`sentence_analysis_json`）。
class SentenceAnalysisView {
  /// 以各字段构造。
  const new({
    this.grammarPattern,
    this.grammarExplanation,
    this.grammarNotes = const <String>[],
    this.keyExpressions = const <SentenceAnalysisItem>[],
    this.similarExamples = const <SentenceAnalysisItem>[],
    this.variations = const <SentenceAnalysisItem>[],
  });

  /// 语法模式（如 `S + V + O`）。
  final String? grammarPattern;

  /// 语法解释。
  final String? grammarExplanation;

  /// 语法要点。
  final List<String> grammarNotes;

  /// 关键表达。
  final List<SentenceAnalysisItem> keyExpressions;

  /// 相似例句。
  final List<SentenceAnalysisItem> similarExamples;

  /// 句式变换。
  final List<SentenceAnalysisItem> variations;

  /// 六个字段是否全为空。
  bool get isEmpty =>
      grammarPattern == null &&
      grammarExplanation == null &&
      grammarNotes.isEmpty &&
      keyExpressions.isEmpty &&
      similarExamples.isEmpty &&
      variations.isEmpty;
}

/// 词条详情的完整视图。
///
/// 字段虽多，但都是「一个词条的全部已知内容」，属于纯数据而非行为；
/// 页面按卡片切分消费，因此不需要再拆成多个数据类。
class WordDetail {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.term,
    required this.normalizedTerm,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.contentType,
    required this.entryType,
    required this.initializationStatus,
    required this.masteryLevel,
    required this.masteryScore,
    required this.isSuspended,
    required this.createdAt,
    required this.definitions,
    required this.pronunciations,
    required this.examples,
    required this.phrases,
    required this.forms,
    required this.synonyms,
    required this.antonyms,
    required this.wordFamily,
    required this.confusedWords,
    required this.roots,
    required this.affixes,
    required this.summary,
    required this.learning,
    required this.sentenceAnalysis,
    required this.tags,
    required this.contentSource,
    this.userNote,
    this.providerMetadataJson,
    this.initializedAt,
    this.sourceCreatedAt,
    this.updatedAt,
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

  /// 内容类型（单词 / 短语 / 句子）。
  final LexicalContentType contentType;

  /// 词条类型（`words.entry_type`）。
  final EntryType entryType;

  /// 初始化状态。
  final InitializationStatus initializationStatus;

  /// 掌握等级。
  final MasteryLevel masteryLevel;

  /// 掌握分。
  final int masteryScore;

  /// 是否已暂停学习。
  final bool isSuspended;

  /// 用户笔记；未写过时为 `null`。
  final String? userNote;

  /// 创建时间（epoch 毫秒）。
  final int createdAt;

  /// 数据源侧的原始创建时间（epoch 毫秒）；导入数据没有该值时为 `null`。
  ///
  /// 与 [createdAt] 分开：前者是「这条内容是什么时候生成的」（词典条目
  /// 的出版时间），后者是「我什么时候把它加进来的」。合成天有时，
  /// 用户看到 2019 年的词条却显示「今天创建」会以为时钟错了。
  final int? sourceCreatedAt;

  /// 词条行最后一次写入的时间（epoch 毫秒）。
  ///
  /// 用于回答「我刚才改的释义到底存进去没有」——[createdAt] 永远不变，
  /// 拿它当「更新时间」会让任何一次编辑都看不出发生过。
  final int? updatedAt;

  /// 释义（已解析、已过滤空文本）。
  final List<DefinitionValue> definitions;

  /// 发音列表。
  final List<PronunciationView> pronunciations;

  /// 例句列表。
  final List<ExampleView> examples;

  /// 短语列表。
  final List<PhraseView> phrases;

  /// 词形变化列表。
  final List<FormView> forms;

  /// 同义词列表。
  final List<RelatedWordView> synonyms;

  /// 反义词列表。
  final List<RelatedWordView> antonyms;

  /// 词族列表。
  final List<RelatedWordView> wordFamily;

  /// 易混词列表。
  final List<RelatedWordView> confusedWords;

  /// 词根列表。
  final List<RootView> roots;

  /// 词缀列表。
  final List<AffixView> affixes;

  /// 词条摘要。
  final SummaryView summary;

  /// 学习辅助信息。
  final LearningView learning;

  /// 句子分析。
  final SentenceAnalysisView sentenceAnalysis;

  /// 标签。
  final List<String> tags;

  /// 数据源调用的原始元数据（JSON 文本，原样展示或调试用）。
  final String? providerMetadataJson;

  /// 内容来源构成。
  final ContentSource contentSource;

  /// 初始化完成时间；未完成时为 `null`。
  final int? initializedAt;

  /// 是否没有任何可展示的内容。
  ///
  /// 详情页据此显示「等待初始化」提示：全部内容为空时页面会只剩头部，
  /// 没有提示的话用户会以为页面加载失败。
  bool get hasNoContent =>
      definitions.isEmpty &&
      examples.isEmpty &&
      phrases.isEmpty &&
      forms.isEmpty &&
      synonyms.isEmpty &&
      antonyms.isEmpty &&
      wordFamily.isEmpty &&
      confusedWords.isEmpty &&
      roots.isEmpty &&
      affixes.isEmpty &&
      summary.isEmpty &&
      learning.isEmpty &&
      sentenceAnalysis.isEmpty &&
      tags.isEmpty;
}

/// 词条的复习统计与 FSRS 卡片状态。
class WordLearningSnapshot {
  /// 以各字段构造；未复习过的词条用默认值。
  const new({
    this.masteryScore = 0,
    this.masteryLevel = MasteryLevel.newWord,
    this.hasCard = false,
    this.dueAt,
    this.stability,
    this.difficulty,
    this.scheduledDays,
    this.reps,
    this.lapses,
    this.fsrsState,
    this.lastReviewAt,
    this.totalReviews = 0,
    this.correctReviews = 0,
    this.isWrongWord = false,
    this.wrongCount = 0,
    this.hardCount = 0,
    this.consecutiveCorrect = 0,
    this.lastWrongAt,
    this.lastCorrectAt,
  });

  /// 掌握分。
  final int masteryScore;

  /// 掌握等级。
  final MasteryLevel masteryLevel;

  /// 是否已有 FSRS 卡片（从未复习过时为 `false`）。
  final bool hasCard;

  /// 下次到期时间（epoch 毫秒）。
  final int? dueAt;

  /// FSRS 稳定性（天）。
  final double? stability;

  /// FSRS 难度（1–10）。
  final double? difficulty;

  /// 已排期间隔（天）。
  final int? scheduledDays;

  /// 累计复习次数。
  final int? reps;

  /// 累计遗忘次数。
  final int? lapses;

  /// FSRS 内部状态序号。
  final int? fsrsState;

  /// 最近一次复习时间。
  final int? lastReviewAt;

  /// 累计作答次数（来自 `word_review_stats`，无记录时按 0 计）。
  final int totalReviews;

  /// 累计答对次数。
  final int correctReviews;

  /// 累计正确率；从未作答时为 `null`（而不是 0，避免显示成「全错」）。
  double? get accuracy =>
      totalReviews == 0 ? null : correctReviews / totalReviews;

  /// 是否处于「活跃错词」状态（`wrong_word_states.active`）。
  ///
  /// 与 [wrongCount] 分开：错词被连续答对若干次后会**解除**，
  /// 但历史错误次数仍然留着——「现在还在错」和「曾经错过」是两件事，
  /// 合成一个数字会让已解除的词在卡片上突然变成 0 次。
  final bool isWrongWord;

  /// 累计错误次数。
  final int wrongCount;

  /// 累计「困难」次数（评分为「模糊」的作答）。
  final int hardCount;

  /// 连续答对次数；达到阈值后错词状态被解除。
  final int consecutiveCorrect;

  /// 最近一次答错时间；从未答错时为 `null`。
  final int? lastWrongAt;

  /// 最近一次答对时间；从未答对时为 `null`。
  final int? lastCorrectAt;

  /// 是否从未进入过错词状态。
  ///
  /// 用来区分「答错过 0 次」和「这张表里根本没有它的行」——
  /// 后者让卡片显示空态而不是一排 0。
  bool get isUntouched =>
      !isWrongWord &&
      wrongCount == 0 &&
      hardCount == 0 &&
      consecutiveCorrect == 0;
}

/// 一条数据源调用记录（详情页「初始化质量」卡的一行）。
///
/// 字段集与 `provider_attempts` 的列一一对应，唯独质量分来自
/// `metadata_json.qualityScore`——它只在 AI 渠道的记录里出现，
/// 词典渠道写的是 `sourceEndpoint` / `fallbackUsed`，拿不到就是 `null`。
class ProviderAttemptView {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.providerId,
    required this.status,
    required this.createdAt,
    this.qualityScore,
    this.durationMs,
    this.fieldsReturned = const <String>[],
    this.errorCode,
    this.errorMessage,
  });

  /// 记录 ID。
  final int id;

  /// 数据源标识；AI 渠道带 `ai:<provider>:<model>` 前缀。
  final String providerId;

  /// 调用结果（成功 / 空 / 失败）。
  final ProviderAttemptStatus status;

  /// 质量分（0–100）；非 AI 渠道没有该值。
  final int? qualityScore;

  /// 调用耗时（毫秒）。
  final int? durationMs;

  /// 这次调用返回了哪些内容字段。
  ///
  /// 「SUCCESS 但一个字段都没返回」是最难排查的失败模式（请求成功、
  /// 质量门也过了，但内容为空），因此单独展示而不是只给一个状态。
  final List<String> fieldsReturned;

  /// 失败时的错误码。
  final String? errorCode;

  /// 失败时的错误说明。
  final String? errorMessage;

  /// 调用时间（epoch 毫秒）。
  final int createdAt;
}

/// 一条复习记录（详情页「复习历史」的一行）。
class ReviewLogEntry {
  /// 以各字段构造。
  const new({
    required this.id,
    required this.reviewedAt,
    required this.rating,
    required this.isCorrect,
    required this.questionType,
    this.durationMs,
  });

  /// 日志 ID。
  final int id;

  /// 作答时间（epoch 毫秒）。
  final int reviewedAt;

  /// 生效评级。
  final ReviewRating rating;

  /// 是否判定为正确。
  final bool isCorrect;

  /// 题型。
  final QuestionType questionType;

  /// 作答耗时（毫秒）；旧数据可能缺失。
  final int? durationMs;
}

/// 仪表盘的全局概览。
class DashboardOverview {
  /// 以各字段构造。
  const new({
    required this.totalWords,
    required this.byMastery,
    required this.dueToday,
    required this.wrongWords,
    required this.reviewedToday,
    required this.streakDays,
    required this.newWordsAvailable,
    required this.completedToday,
    required this.todayGoalTotal,
    required this.todayAccuracy,
    required this.failedWords,
  });

  /// 词条总数。
  final int totalWords;

  /// 各掌握等级的词条数（只含实际出现过的等级）。
  final Map<MasteryLevel, int> byMastery;

  /// 今日到期且可复习的卡片数。
  final int dueToday;

  /// 活跃错词数。
  final int wrongWords;

  /// 今日已作答题数。
  final int reviewedToday;

  /// 连续复习天数。
  final int streakDays;

  /// 尚未建立复习卡片、可以开始学的新词数。
  final int newWordsAvailable;

  /// 今日已处理的题数（已作答 + 用户主动跳过）。
  ///
  /// 系统收尾的跳过（会话过期、进度重置）不算：它们不是用户的意愿，
  /// 计入会让「今日完成度」凭空前进。
  final int completedToday;

  /// 今日目标总题数 = 今日已处理 + 今日还剩。
  ///
  /// 目标是**当天结束时应当完成的累计量**，而不是「今天新开的题数」；
  /// 否则上午看到 0/20、下午看到 0/20，进度条永远不会动。
  /// 剩余部分由调用方用 [DailyStudyPlan.plannedTotal] 注入，本 DAO
  /// 不重算抽题逻辑（那会让首页与学习页的题数各算各的）。
  final int todayGoalTotal;

  /// 今日正确率（0–1）；今日没有作答时为 `0`。
  final double todayAccuracy;

  /// 初始化失败的词条数。
  ///
  /// 与「今日到期」「错词」不同，这不是学习指标而是**待修的故障**，
  /// 首页用它提示用户去初始化页处理。
  final int failedWords;
}

// ═══════════════════════════════════════════════════════════════
// SQL
// ═══════════════════════════════════════════════════════════════

/// 详情查询的列清单。
///
/// `LEFT JOIN` 而非 `JOIN`：初始化尚未产出内容的词条也要能打开详情页，
/// 否则用户会看到一个「查不到」的空态，而词条其实存在。
///
/// 这几条 SQL 都没有 `$`（JSON 路径），因此不用 `r'''` 前缀——
/// 加了反而触发 `unnecessary_raw_strings`。只有真的取了 JSON 路径的
/// [_providerAttemptsSql] 才用 raw 字符串。
const String _detailSql = '''
SELECT
  w.id, w.term, w.normalized_term, w.source_language, w.target_language,
  w.content_type, w.entry_type, w.initialization_status, w.mastery_level,
  w.mastery_score, w.is_suspended, w.user_note, w.created_at,
  w.source_created_at, w.updated_at,
  c.definitions_json, c.pronunciations_json, c.examples_json,
  c.phrases_json, c.forms_json, c.synonyms_json, c.antonyms_json,
  c.word_family_json, c.confused_words_json, c.roots_json, c.affixes_json,
  c.summary_json, c.learning_json, c.sentence_analysis_json, c.tags_json,
  c.provider_metadata_json, c.content_source, c.initialized_at
FROM words w
LEFT JOIN word_contents c ON c.word_id = w.id
WHERE w.id = ?''';

/// 学习情况查询：卡片状态、累计统计与错词状态一次取回。
///
/// `wrong_word_states` 是**按需展示**的：绝大多数词条从来没有答错过，
/// 把错词状态内联进主查询会让每张详情卡都多一次 LEFT JOIN 的成本，
/// 而错词状态本身也不是「学习进度」的一部分——它是「这个词难在哪」的
/// 另一维度。
const String _snapshotSql = '''
SELECT
  w.mastery_score, w.mastery_level,
  rc.due_at, rc.stability, rc.difficulty, rc.scheduled_days, rc.reps,
  rc.lapses, rc.fsrs_state, rc.last_review_at,
  s.total_reviews, s.correct_reviews,
  ws.active, ws.wrong_count, ws.hard_count, ws.consecutive_correct,
  ws.last_wrong_at, ws.last_correct_at
FROM words w
LEFT JOIN review_cards rc ON rc.word_id = w.id
LEFT JOIN word_review_stats s ON s.word_id = w.id
LEFT JOIN wrong_word_states ws ON ws.word_id = w.id
WHERE w.id = ?''';

/// 初始化质量查询：某个词条最近的数据源调用记录。
///
/// **`provider_attempts` 之前完全没有读取路径**——worker 只写不读，
/// 于是「AI 返回了内容却被质量门丢弃」这类问题在界面上没有任何线索。
/// 这条 SQL 是那张表的第一个消费者。
///
/// 质量分不在列上而在 `metadata_json.qualityScore` 里（只有 AI 渠道写），
/// 因此用 `json_extract` 取——这条 SQL 带 JSON 路径，用 raw 字符串。
const String _providerAttemptsSql = r'''
SELECT
  id, provider_id, status, duration_ms, error_code, error_message,
  fields_returned_json, created_at,
  json_extract(metadata_json, '$.qualityScore') AS quality_score
FROM provider_attempts
WHERE word_id = ?
ORDER BY created_at DESC, id DESC
LIMIT ?''';

/// 复习历史查询：按时间倒序，`LIMIT ?` 由调用方给定。
const String _recentLogsSql = '''
SELECT id, reviewed_at, rating, is_correct, question_type, duration_ms
FROM review_logs
WHERE word_id = ?
ORDER BY reviewed_at DESC, id DESC
LIMIT ?''';

/// 系统收尾写入的跳过原因：会话过期。
///
/// 与 `StudyDao` 的同名常量逐字一致（两处都不是 `public`，只能各留一份，
/// 靠这里与那里的注释互相对照）。它们**不计入**今日已处理：超时收尾时
/// 用户并没有主动放弃，把它们算成完成会让进度条虚高。
const String _sessionExpiredSkipReason = 'SESSION_EXPIRED';

/// 系统收尾写入的跳过原因：学习进度被重置。
const String _progressResetSkipReason = 'PROGRESS_RESET';

/// 概览查询。
///
/// 计数用标量子查询一次取回，省去多次往返；`?` 的顺序为
/// 「当前时间」「今日零点」「今日零点」「FAILED」，与
/// [WordDetailDao.overview] 的绑定顺序一致。
///
/// `READY`/`PARTIAL` 的过滤条件与 `StudyDao` 的候选准入条件保持一致：
/// 未就绪的词条不该被算进「今天要复习多少」。
const String _overviewSql = '''
SELECT
  (SELECT count(*) FROM words) AS total_words,
  (SELECT count(*) FROM review_cards rc
     JOIN words w ON w.id = rc.word_id
    WHERE rc.due_at <= ?
      AND w.is_suspended = 0
      AND w.initialization_status IN ('READY', 'PARTIAL')) AS due_today,
  (SELECT count(*) FROM wrong_word_states WHERE active = 1) AS wrong_words,
  (SELECT count(*) FROM review_logs WHERE reviewed_at >= ?) AS reviewed_today,
  (SELECT count(*) FROM study_session_items i
    WHERE i.status = 'SKIPPED'
      AND i.answered_at >= ?
      AND i.skip_reason IS NOT ?
      AND i.skip_reason IS NOT ?) AS skipped_today,
  (SELECT count(*) FROM review_logs
    WHERE reviewed_at >= ? AND is_correct = 1) AS correct_today,
  (SELECT count(*) FROM words w
    WHERE w.is_suspended = 0
      AND w.initialization_status IN ('READY', 'PARTIAL')
      AND NOT EXISTS (
        SELECT 1 FROM review_cards rc WHERE rc.word_id = w.id
      )) AS new_words,
  (SELECT count(*) FROM words
    WHERE initialization_status = ?) AS failed_words''';

// ═══════════════════════════════════════════════════════════════
// DAO
// ═══════════════════════════════════════════════════════════════

/// 词条详情的只读查询入口。
class WordDetailDao {
  /// 以数据库构造。
  const new(this._db);

  final AppDatabase _db;

  /// 读取词条详情；词条不存在时返回 `null`。
  Future<WordDetail?> find(int wordId) async {
    final row = await _db
        .customSelect(
          _detailSql,
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingleOrNull();
    return row == null ? null : _mapDetail(row);
  }

  /// 读取复习统计、FSRS 卡片状态与错词状态。
  ///
  /// 词条不存在时返回全默认值而非 `null`：调用方（详情页）已经用
  /// [find] 判过存在性，这里再抛一个可空类型只会让卡片多写一层判空。
  Future<WordLearningSnapshot> learningSnapshot(int wordId) async {
    final row = await _db
        .customSelect(
          _snapshotSql,
          variables: <Variable<Object>>[Variable<int>(wordId)],
        )
        .getSingleOrNull();
    if (row == null) return const WordLearningSnapshot();

    final dueAt = row.readNullable<int>('due_at');
    return WordLearningSnapshot(
      masteryScore: row.read<int>('mastery_score'),
      masteryLevel:
          wireLookup(MasteryLevel.values, row.read<String>('mastery_level')) ??
          MasteryLevel.newWord,
      hasCard: dueAt != null,
      dueAt: dueAt,
      stability: row.readNullable<double>('stability'),
      difficulty: row.readNullable<double>('difficulty'),
      scheduledDays: row.readNullable<int>('scheduled_days'),
      reps: row.readNullable<int>('reps'),
      lapses: row.readNullable<int>('lapses'),
      fsrsState: row.readNullable<int>('fsrs_state'),
      lastReviewAt: row.readNullable<int>('last_review_at'),
      totalReviews: row.readNullable<int>('total_reviews') ?? 0,
      correctReviews: row.readNullable<int>('correct_reviews') ?? 0,
      isWrongWord: row.readNullable<bool>('active') ?? false,
      wrongCount: row.readNullable<int>('wrong_count') ?? 0,
      hardCount: row.readNullable<int>('hard_count') ?? 0,
      consecutiveCorrect: row.readNullable<int>('consecutive_correct') ?? 0,
      lastWrongAt: row.readNullable<int>('last_wrong_at'),
      lastCorrectAt: row.readNullable<int>('last_correct_at'),
    );
  }

  /// 读取某个词条最近的数据源调用记录，按调用时间倒序。
  ///
  /// [limit] 默认 [providerAttemptCardLimit]：卡片是排查工具，取最近若干条
  /// 足以定位「哪一次调用出的问题」，全量拉取在重试过的词条上会到上百条。
  Future<List<ProviderAttemptView>> providerAttempts(
    int wordId, {
    int limit = providerAttemptCardLimit,
  }) async {
    final rows = await _db
        .customSelect(
          _providerAttemptsSql,
          variables: <Variable<Object>>[
            Variable<int>(wordId),
            Variable<int>(limit),
          ],
        )
        .get();
    return rows.map(_mapAttempt).toList(growable: false);
  }

  /// 读取最近的复习记录，按时间倒序。
  Future<List<ReviewLogEntry>> recentLogs(
    int wordId, {
    int limit = reviewHistoryLimit,
  }) async {
    final rows = await _db
        .customSelect(
          _recentLogsSql,
          variables: <Variable<Object>>[
            Variable<int>(wordId),
            Variable<int>(limit),
          ],
        )
        .get();
    return rows.map(_mapLog).toList(growable: false);
  }

  /// 全局概览：词条总数、掌握分布、今日到期、错词、今日已答、连续天数、
  /// 新词、今日完成度、今日正确率与初始化失败数。
  ///
  /// [plannedRemaining] 由调用方从 [DailyStudyPlan.plannedTotal] 取，
  /// 本方法不重算抽题——配额与随机抽题属于服务层，DAO 再实现一遍必然
  /// 与首页显示的题数对不上。
  Future<DashboardOverview> overview(
    int now, {
    int plannedRemaining = 0,
  }) async {
    final row = await _overviewRow(now);
    final completedToday =
        row.read<int>('reviewed_today') + row.read<int>('skipped_today');

    return DashboardOverview(
      totalWords: row.read<int>('total_words'),
      byMastery: await WordDao(_db).countByMastery(),
      dueToday: row.read<int>('due_today'),
      wrongWords: row.read<int>('wrong_words'),
      reviewedToday: row.read<int>('reviewed_today'),
      streakDays: await _streakDays(now),
      newWordsAvailable: row.read<int>('new_words'),
      completedToday: completedToday,
      todayGoalTotal: completedToday + plannedRemaining,
      todayAccuracy: _accuracyOf(
        correct: row.read<int>('correct_today'),
        total: row.read<int>('reviewed_today'),
      ),
      failedWords: row.read<int>('failed_words'),
    );
  }

  /// 执行概览查询。
  Future<QueryRow> _overviewRow(int now) => _db
      .customSelect(
        _overviewSql,
        variables: <Variable<Object>>[
          Variable<int>(now),
          Variable<int>(startOfLocalDay(now)),
          Variable<int>(startOfLocalDay(now)),
          const Variable<String>(_sessionExpiredSkipReason),
          const Variable<String>(_progressResetSkipReason),
          Variable<int>(startOfLocalDay(now)),
          Variable<String>(InitializationStatus.failed.wire),
        ],
      )
      .getSingle();

  /// 今日正确率。
  ///
  /// 没有作答时给 `0` 而不是 `null`：首页把它当数值直接参与布局，
  /// 可空会让「今日完成度」一行多出一套空态分支。
  double _accuracyOf({required int correct, required int total}) =>
      total == 0 ? 0 : correct / total;

  /// 连续复习天数：从今天（或昨天）起逐日向前数。
  ///
  /// 必须走 [localDayOrdinal] 而不是按 `dayMs` 相减——夏令时切换日只有
  /// 23 小时，直接按毫秒折算会把跨日边界算错（见 `core/date_key.dart`）。
  ///
  /// 「今天还没复习」不算断签：昨天学过、今天尚未开始时仍显示连续，
  /// 否则用户每天早上打开都会看到 0，连续天数就失去了激励意义。
  Future<int> _streakDays(int now) async {
    final rows = await _db
        .customSelect(
          'SELECT DISTINCT reviewed_at FROM review_logs '
          'ORDER BY reviewed_at DESC',
        )
        .get();
    final days = <int>{
      for (final row in rows) localDayOrdinal(row.read<int>('reviewed_at')),
    };
    final today = localDayOrdinal(now);
    var cursor = days.contains(today) ? today : today - 1;
    var streak = 0;
    while (days.contains(cursor)) {
      streak += 1;
      cursor -= 1;
    }
    return streak;
  }

  WordDetail _mapDetail(QueryRow row) => WordDetail(
    id: row.read<int>('id'),
    term: row.read<String>('term'),
    normalizedTerm: row.read<String>('normalized_term'),
    sourceLanguage: row.read<String>('source_language'),
    targetLanguage: row.read<String>('target_language'),
    contentType:
        wireLookup(
          LexicalContentType.values,
          row.read<String>('content_type'),
        ) ??
        LexicalContentType.word,
    entryType:
        wireLookup(EntryType.values, row.read<String>('entry_type')) ??
        EntryType.word,
    initializationStatus:
        wireLookup(
          InitializationStatus.values,
          row.read<String>('initialization_status'),
        ) ??
        InitializationStatus.pending,
    masteryLevel:
        wireLookup(MasteryLevel.values, row.read<String>('mastery_level')) ??
        MasteryLevel.newWord,
    masteryScore: row.read<int>('mastery_score'),
    isSuspended: row.read<bool>('is_suspended'),
    userNote: row.readNullable<String>('user_note'),
    createdAt: row.read<int>('created_at'),
    sourceCreatedAt: row.readNullable<int>('source_created_at'),
    updatedAt: row.readNullable<int>('updated_at'),
    definitions: parseDefinitionsJson(
      row.readNullable<String>('definitions_json'),
    ),
    pronunciations: parsePronunciations(
      row.readNullable<String>('pronunciations_json'),
    ),
    examples: parseDetailExamples(row.readNullable<String>('examples_json')),
    phrases: _parsePhrases(row.readNullable<String>('phrases_json')),
    forms: _parseForms(row.readNullable<String>('forms_json')),
    synonyms: _parseRelated(row.readNullable<String>('synonyms_json')),
    antonyms: _parseRelated(row.readNullable<String>('antonyms_json')),
    wordFamily: _parseRelated(row.readNullable<String>('word_family_json')),
    confusedWords: _parseRelated(
      row.readNullable<String>('confused_words_json'),
    ),
    roots: _parseRoots(row.readNullable<String>('roots_json')),
    affixes: _parseAffixes(row.readNullable<String>('affixes_json')),
    summary: _parseSummary(row.readNullable<String>('summary_json')),
    learning: _parseLearning(row.readNullable<String>('learning_json')),
    sentenceAnalysis: _parseSentenceAnalysis(
      row.readNullable<String>('sentence_analysis_json'),
    ),
    tags: parseTextList(decodeJson(row.readNullable<String>('tags_json'))),
    providerMetadataJson: row.readNullable<String>('provider_metadata_json'),
    contentSource:
        wireLookup(
          ContentSource.values,
          // 没有 word_contents 行时该列为 NULL，必须按可空读取。
          row.readNullable<String>('content_source') ?? '',
        ) ??
        ContentSource.mixed,
    initializedAt: row.readNullable<int>('initialized_at'),
  );

  ReviewLogEntry _mapLog(QueryRow row) => ReviewLogEntry(
    id: row.read<int>('id'),
    reviewedAt: row.read<int>('reviewed_at'),
    rating:
        wireLookup(ReviewRating.values, row.read<String>('rating')) ??
        ReviewRating.good,
    isCorrect: row.read<bool>('is_correct'),
    questionType:
        wireLookup(QuestionType.values, row.read<String>('question_type')) ??
        QuestionType.enToZh,
    durationMs: row.readNullable<int>('duration_ms'),
  );

  /// 映射一条数据源调用记录。
  ///
  /// 状态字面量不认识时**退化为 [ProviderAttemptStatus.empty]**而不是跳过：
  /// 审计记录的价值恰恰在于「出现了没预料到的东西」，把它藏起来会让
  /// 排查从零开始。
  ProviderAttemptView _mapAttempt(QueryRow row) => ProviderAttemptView(
    id: row.read<int>('id'),
    providerId: row.read<String>('provider_id'),
    status:
        wireLookup(ProviderAttemptStatus.values, row.read<String>('status')) ??
        ProviderAttemptStatus.empty,
    qualityScore: _qualityScoreOf(row),
    durationMs: row.readNullable<int>('duration_ms'),
    fieldsReturned: parseTextList(
      decodeJson(row.readNullable<String>('fields_returned_json')),
    ),
    errorCode: row.readNullable<String>('error_code'),
    errorMessage: row.readNullable<String>('error_message'),
    createdAt: row.read<int>('created_at'),
  );

  /// 质量分：只接受整数，脏值按「没有质量分」处理。
  ///
  /// `json_extract` 在路径不存在或值不是数字时返回 `null`，但脏数据里
  /// 也可能出现字符串形式的分数；强行解析会让一张审计卡片因为一个字段
  /// 整张渲染不出来。
  ///
  /// 读的是 `row.data` 而不是 `row.readNullable<Object>`：Drift 需要由
  /// 列的类型推出 Dart 类型映射，而 `Object` 没有对应项，会在运行期抛
  /// 「Could not find a matching SQL type for Object」。绕开类型映射、
  /// 直接看原始值，才是这一列「可能是任意 JSON 标量」的正确读法。
  int? _qualityScoreOf(QueryRow row) {
    final raw = row.data['quality_score'];
    return raw is int ? raw : null;
  }
}

// ═══════════════════════════════════════════════════════════════
// JSON 解析
//
// 全部按「字段可能是字符串，也可能是对象」处理：旧版
// `dictionary/content.ts` 的 `normalizeRelatedItems` 就同时接受
// `["apple"]` 与 `[{word: "apple"}]` 两种历史形态，纯本地版直接读旧备份，
// 两种形态都会遇到。缺少必需字段的元素一律丢弃，而不是渲染半行空白。
// ═══════════════════════════════════════════════════════════════

/// 解析相关词条列表（同义词 / 反义词 / 词族 / 易混词）。
List<RelatedWordView> _parseRelated(String? raw) {
  final result = <RelatedWordView>[];
  for (final item in decodeJsonList(raw)) {
    final word = relatedWordOf(item);
    if (word.isEmpty) continue;
    result.add(
      RelatedWordView(
        word: word,
        translation: fieldOf(item, 'translation'),
        partOfSpeech: fieldOf(item, 'partOfSpeech'),
        relation: fieldOf(item, 'relation'),
        source: fieldOf(item, 'source'),
        difference: fieldOf(item, 'difference'),
      ),
    );
  }
  return result;
}

/// 解析详情页例句列表（`examples_json`），跳过不可用的条目。
///
/// **不复用 `content_parse.dart` 的 `parseExamples`**：那一支是学习会话
/// 的加载路径，按「一次会话只拖需要的字段」刻意做到最简；详情页要多展示
/// 难度与义项编号。两条路径共用 `decodeJsonList` / `textOf` / `fieldOf`
/// 这些原语，且**丢弃规则完全一致**（同一个 [isUsableExample]），
/// 因此同一份 JSON 在两处解析出的例句集合永远相同。
List<ExampleView> parseDetailExamples(String? raw) {
  final result = <ExampleView>[];
  for (final item in decodeJsonList(raw)) {
    if (item is! Map) continue;
    final sentence = textOf(item['sentence']);
    if (sentence.isEmpty) continue;
    result.add(
      ExampleView(
        sentence: sentence,
        translation: fieldOf(item, 'translation'),
        senseId: fieldOf(item, 'senseId'),
        difficulty: fieldOf(item, 'difficulty'),
      ),
    );
  }
  return result;
}

/// 详情页可见的例句在原始 JSON 数组中的下标。
///
/// 界面按 [parseDetailExamples] 的结果逐条渲染，而该解析会丢弃
/// 「非对象」与「句子为空」的条目——两个下标并不总是相等。删除与翻译
/// 必须先用本函数把界面下标换算回真实下标，否则会作用到隔壁那条。
List<int> detailExamplePositions(String? raw) {
  final result = <int>[];
  final items = decodeJsonList(raw);
  for (var index = 0; index < items.length; index += 1) {
    if (isUsableExample(items[index])) result.add(index);
  }
  return result;
}

/// 一条例句是否值得展示：必须是对象且句子非空。
///
/// 判据抽成具名函数而不是各写一遍：解析与下标换算必须永远一致，
/// 一旦这里放宽了而那里没放宽，删除按钮就会删错条目。
bool isUsableExample(Object? item) =>
    item is Map && textOf(item['sentence']).isNotEmpty;

/// 解析短语列表，跳过短语文本为空的条目。
List<PhraseView> _parsePhrases(String? raw) {
  final result = <PhraseView>[];
  for (final item in decodeJsonList(raw)) {
    final phrase = textOf(item);
    if (phrase.isEmpty) continue;
    result.add(
      PhraseView(
        phrase: phrase,
        translation: fieldOf(item, 'translation'),
        source: fieldOf(item, 'source'),
      ),
    );
  }
  return result;
}

/// 解析词形变化列表，跳过形态为空的条目。
List<FormView> _parseForms(String? raw) {
  final result = <FormView>[];
  for (final item in decodeJsonList(raw)) {
    final form = textOf(item);
    if (form.isEmpty) continue;
    result.add(
      FormView(
        form: form,
        label: fieldOf(item, 'type') ?? fieldOf(item, 'label'),
        translation: fieldOf(item, 'translation'),
      ),
    );
  }
  return result;
}

/// 解析词根列表；缺 `root` 或 `meaning` 的条目丢弃。
List<RootView> _parseRoots(String? raw) {
  final result = <RootView>[];
  for (final item in decodeJsonList(raw)) {
    if (item is! Map) continue;
    final root = textOf(item['root']);
    final meaning = textOf(item['meaning']);
    if (root.isEmpty || meaning.isEmpty) continue;
    result.add(
      RootView(
        root: root,
        meaning: meaning,
        origin: nullableTextOf(item['origin']),
        source: nullableTextOf(item['source']),
      ),
    );
  }
  return result;
}

/// 解析词缀列表；缺 `value`、`meaning` 或 `type` 的条目丢弃。
///
/// `type` 不是 `PREFIX`/`SUFFIX` 时同样丢弃：界面上前缀与后缀分区展示，
/// 归错区的词缀比不显示更糟。
List<AffixView> _parseAffixes(String? raw) {
  final result = <AffixView>[];
  for (final item in decodeJsonList(raw)) {
    if (item is! Map) continue;
    final value = textOf(item['value']);
    final meaning = textOf(item['meaning']);
    final kind = wireLookup(
      AffixKind.values,
      textOf(item['type']).toUpperCase(),
    );
    if (value.isEmpty || meaning.isEmpty || kind == null) continue;
    result.add(
      AffixView(
        value: value,
        meaning: meaning,
        kind: kind,
        source: nullableTextOf(item['source']),
      ),
    );
  }
  return result;
}

/// 解析摘要对象；解析失败时返回空结构。
SummaryView _parseSummary(String? raw) {
  final map = decodeJsonMap(raw);
  return SummaryView(
    shortDefinition: nullableTextOf(map['shortDefinition']),
    translation: nullableTextOf(map['translation']),
    cefrLevel: nullableTextOf(map['cefrLevel']),
    frequency: nullableTextOf(map['frequency']),
  );
}

/// 解析学习辅助对象；解析失败时返回空结构。
LearningView _parseLearning(String? raw) {
  final map = decodeJsonMap(raw);
  return LearningView(
    pronunciationTip: nullableTextOf(map['pronunciationTip']),
    mnemonic: nullableTextOf(map['mnemonic']),
    commonMistakes: parseTextList(map['commonMistakes']),
  );
}

/// 解析句子分析对象；解析失败时返回空结构。
SentenceAnalysisView _parseSentenceAnalysis(String? raw) {
  final map = decodeJsonMap(raw);
  return SentenceAnalysisView(
    grammarPattern: nullableTextOf(map['grammarPattern']),
    grammarExplanation: nullableTextOf(map['grammarExplanation']),
    grammarNotes: parseTextList(map['grammarNotes']),
    keyExpressions: _parseAnalysisItems(map['keyExpressions']),
    similarExamples: _parseAnalysisItems(map['similarExamples']),
    variations: _parseAnalysisItems(map['variations']),
  );
}

/// 解析句子分析里的条目列表（字符串与对象两种形态都接受）。
///
/// 正文取 [textOf]，它按 `textKeys` 顺序扫描，因此真实备份里的
/// `{"expression": ...}`（关键表达）与 `{"sentence": ...}`（相似例句 /
/// 句式变换）都能取到正文；三个附注字段按各自的键单独读。
List<SentenceAnalysisItem> _parseAnalysisItems(Object? value) {
  if (value is! List) return const <SentenceAnalysisItem>[];
  final result = <SentenceAnalysisItem>[];
  for (final item in value) {
    final text = textOf(item);
    if (text.isEmpty) continue;
    result.add(
      SentenceAnalysisItem(
        text: text,
        label: fieldOf(item, 'type') ?? fieldOf(item, 'label'),
        translation: fieldOf(item, 'translation'),
        meaning: fieldOf(item, 'meaning'),
        note: fieldOf(item, 'note'),
        focus: fieldOf(item, 'focus'),
      ),
    );
  }
  return result;
}
