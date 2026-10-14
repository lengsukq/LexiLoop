/// 领域枚举。
///
/// 每个取值都带一个显式的 [WireEnum.wire] 稳定标识，与旧版 PostgreSQL 的
/// CHECK 约束逐字对应（大写下划线）。**显式而非由枚举名推导**，原因有二：
/// 1. Dart 保留字 `new` 无法作为枚举名，`MasteryLevel.newWord` 必须映射到 `NEW`；
/// 2. 驼峰转大写下划线无法还原 `EN_TO_ZH`、`SKIP_EXISTING` 这类形态。
///
/// 显式映射还有个好处：可以逐条对照旧版 CHECK 约束做审计。
///
/// 本文件必须保持**纯 Dart**：不得引入 Flutter、Drift 或任何 IO 包，
/// 由 `test/architecture/` 的守卫测试强制。
library;

/// 带有稳定存储标识的枚举。
///
/// 实现该接口的枚举可被 Drift 的 `WireEnumConverter` 直接映射为 TEXT 列。
abstract interface class WireEnum {
  /// 数据库与备份 JSON 中使用的稳定标识。
  String get wire;
}

/// 按 wire 值反查枚举，未知值返回 `null`。
T? wireLookup<T extends WireEnum>(List<T> values, String wire) {
  for (final value in values) {
    if (value.wire == wire) return value;
  }
  return null;
}

/// 词条初始化状态。
enum InitializationStatus implements WireEnum {
  /// 尚未进入队列。
  pending('PENDING'),

  /// 已入队等待处理。
  queued('QUEUED'),

  /// 正在处理中。
  running('RUNNING'),

  /// 内容完整可用。
  ready('READY'),

  /// 内容部分可用。
  partial('PARTIAL'),

  /// 初始化失败。
  failed('FAILED'),

  /// 数据源被禁用。
  disabled('DISABLED');

  new(this.wire);

  @override
  final String wire;
}

/// 初始化模式（词条级）。
enum InitializationMode implements WireEnum {
  /// 已有内容则跳过。
  skipInitialized('SKIP_INITIALIZED'),

  /// 只补缺失字段。
  fillMissingFields('FILL_MISSING_FIELDS'),

  /// 强制覆盖。
  forceOverwrite('FORCE_OVERWRITE');

  new(this.wire);

  @override
  final String wire;
}

/// 导入模式（批次级）。
///
/// 注意与 [InitializationMode] 的取值**不同名**，旧版即如此。
enum ImportMode implements WireEnum {
  /// 仅新增，不碰已有词条。
  skipExisting('SKIP_EXISTING'),

  /// 新增 + 已有词条补字段。
  fillMissing('FILL_MISSING'),

  /// 重新获取已有词条的词典内容，保留学习进度。
  forceDictionaryRefresh('FORCE_DICTIONARY_REFRESH');

  new(this.wire);

  @override
  final String wire;
}

/// 掌握等级。
enum MasteryLevel implements WireEnum {
  /// 未学习。
  ///
  /// 枚举名不能叫 `new`（Dart 保留字），故用 `newWord` 映射到 `NEW`。
  newWord('NEW'),

  /// 学习中。
  learning('LEARNING'),

  /// 熟悉。
  familiar('FAMILIAR'),

  /// 熟练。
  proficient('PROFICIENT'),

  /// 已掌握。
  mastered('MASTERED');

  new(this.wire);

  @override
  final String wire;
}

/// 复习评分。
enum ReviewRating implements WireEnum {
  /// 完全忘记。
  again('AGAIN'),

  /// 模糊。
  hard('HARD'),

  /// 良好。
  good('GOOD'),

  /// 轻松。
  easy('EASY');

  new(this.wire);

  @override
  final String wire;
}

/// 学习模式。
///
/// 旧版 PostgreSQL 的 CHECK 只列了 6 个值，但代码实际会写入
/// [sentenceReview] 与 [aiRecommended]，属于源端缺陷（写入会被约束拒绝）。
/// 本版按 8 个值实现。
enum StudyMode implements WireEnum {
  /// 每日综合队列。
  daily('DAILY'),

  /// 仅新词。
  newWords('NEW_WORDS'),

  /// 仅到期复习。
  dueReview('DUE_REVIEW'),

  /// 仅错词。
  wrongWords('WRONG_WORDS'),

  /// 听力专项。
  listening('LISTENING'),

  /// 拼写专项。
  spelling('SPELLING'),

  /// 句子复习。
  sentenceReview('SENTENCE_REVIEW'),

  /// AI 推荐。
  aiRecommended('AI_RECOMMENDED');

  new(this.wire);

  @override
  final String wire;
}

/// 题型。
enum QuestionType implements WireEnum {
  /// 英译中（自评）。
  enToZh('EN_TO_ZH'),

  /// 英译中（选择）。
  enToZhChoice('EN_TO_ZH_CHOICE'),

  /// 中译英（选择）。
  zhToEnChoice('ZH_TO_EN_CHOICE'),

  /// 中译英（拼写）。
  zhToEnSpelling('ZH_TO_EN_SPELLING'),

  /// 听音拼写。
  listeningSpelling('LISTENING_SPELLING'),

  /// 例句填空。
  clozeSentence('CLOZE_SENTENCE'),

  /// 听音选择。
  listeningChoice('LISTENING_CHOICE'),

  /// 字母库拼词。
  letterBank('LETTER_BANK');

  new(this.wire);

  @override
  final String wire;
}

/// 词条类型。
///
/// 旧版 `words.entry_type` 的 CHECK 只有 WORD/PHRASE 两值（句子存为 PHRASE），
/// 而 `words.content_type` 有三值。本版按语义拆开：[EntryType] 对应 entry_type，
/// [LexicalContentType] 对应 content_type。
enum EntryType implements WireEnum {
  /// 单词。
  word('WORD'),

  /// 短语（句子在 entry_type 中也归入此类）。
  phrase('PHRASE');

  new(this.wire);

  @override
  final String wire;
}

/// 内容类型（`words.content_type`）。
enum LexicalContentType implements WireEnum {
  /// 单词。
  word('WORD'),

  /// 短语。
  phrase('PHRASE'),

  /// 句子。
  sentence('SENTENCE');

  new(this.wire);

  @override
  final String wire;
}

/// 会话题目所属的任务类型。
enum StudyTaskType implements WireEnum {
  /// 新词。
  newWord('NEW'),

  /// 到期复习。
  review('REVIEW'),

  /// 错词。
  wrong('WRONG'),

  /// 听力。
  listening('LISTENING'),

  /// 拼写。
  spelling('SPELLING');

  new(this.wire);

  @override
  final String wire;
}

/// 会话题目的作答状态。
enum StudyItemStatus implements WireEnum {
  /// 待作答。
  pending('PENDING'),

  /// 已作答。
  answered('ANSWERED'),

  /// 已跳过。
  skipped('SKIPPED');

  new(this.wire);

  @override
  final String wire;
}

/// 初始化任务的任务类型。
enum JobTaskType implements WireEnum {
  /// 词条内容初始化。
  initialize('INITIALIZE'),

  /// 生成中文助记。
  mnemonic('MNEMONIC'),

  /// 翻译例句。
  exampleTranslations('EXAMPLE_TRANSLATIONS');

  new(this.wire);

  @override
  final String wire;
}

/// 数据源调用策略。
enum ProviderStrategy implements WireEnum {
  /// 并发调用全部数据源后合并。
  parallelMerge('PARALLEL_MERGE'),

  /// 按优先级顺序调用，达标即停。
  priorityFallback('PRIORITY_FALLBACK');

  new(this.wire);

  @override
  final String wire;
}

/// 导入批次状态。
enum ImportBatchStatus implements WireEnum {
  /// 已提交但尚未完成处理。
  pending('PENDING'),

  /// 已提交完成。
  committed('COMMITTED'),

  /// 处理失败。
  failed('FAILED'),

  /// 已撤销。
  rolledBack('ROLLED_BACK');

  new(this.wire);

  @override
  final String wire;
}

/// 导入行的处理结果。
enum ImportRowStatus implements WireEnum {
  /// 校验不通过。
  invalid('INVALID'),

  /// 文件内重复。
  duplicate('DUPLICATE'),

  /// 新词条。
  newWord('NEW'),

  /// 已存在词条。
  existing('EXISTING'),

  /// 已导入。
  imported('IMPORTED'),

  /// 处理出错。
  error('ERROR');

  new(this.wire);

  @override
  final String wire;
}

/// 数据源单次调用的结果。
enum ProviderAttemptStatus implements WireEnum {
  /// 成功返回内容。
  success('SUCCESS'),

  /// 调用成功但无内容。
  empty('EMPTY'),

  /// 调用失败。
  failed('FAILED');

  new(this.wire);

  @override
  final String wire;
}

/// 内容来源构成。
enum ContentSource implements WireEnum {
  /// 全部来自 AI。
  aiOnly('AI_ONLY'),

  /// AI 与词典混合。
  mixed('MIXED'),

  /// 全部来自词典。
  dictionaryOnly('DICTIONARY_ONLY');

  new(this.wire);

  @override
  final String wire;
}

/// 每日建议的生成方式。
enum SuggestionGenerator implements WireEnum {
  /// 由大模型生成。
  ai('AI'),

  /// 由本地规则生成。
  ruleBased('RULE_BASED');

  new(this.wire);

  @override
  final String wire;
}

/// 发音口音。
enum Accent implements WireEnum {
  /// 美音。
  us('US'),

  /// 英音。
  uk('UK');

  new(this.wire);

  @override
  final String wire;
}
