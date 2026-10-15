/// 全应用数值常量的唯一出处。
///
/// **为什么所有数字都在这里**：`docs/CLEAN_CODE_BASELINE.md` 记录旧版最严重的
/// 问题之一是魔法数字散落——`suggestions/candidates.ts` 一个表达式里有 13 个裸权重、
/// `games/completion.ts` 与 `matching/service.ts` 各有一套计分权重、`max_attempts`
/// 在不同路径硬编码成 2 和 5。集中之后这些值可调、可测、可对照。
///
/// **约束**：`lib/domain/` 与 `lib/services/` 中不得出现裸数字字面量
/// （`0`、`1`、`-1` 除外），由 `test/architecture/` 的守卫测试强制。
///
/// 每个常量的注释标注来源，便于与旧版实现逐条对照。
library;

import 'package:lexiloop/core/time.dart';

// ═══════════════════════════════════════════════════════════════
// 词条归一化（对应旧版 modules/imports/normalizer.ts）
// ═══════════════════════════════════════════════════════════════

/// 需要做 locale 小写化的语言代码。
///
/// 旧版用 `toLocaleLowerCase(locale)`；Dart 的 `toLowerCase()` 无 locale 参数，
/// 对这些语言两者行为一致（土耳其语 İ 问题不在集合内）。
const Set<String> lowercaseLanguages = <String>{
  'en',
  'nl',
  'fr',
  'de',
  'es',
  'it',
  'pt',
  'sv',
  'da',
  'no',
};

/// 词条文本长度上限，超出视为无效行。
const int termMaxLength = 300;

/// 语言字段长度上限。
const int languageFieldMaxLength = 50;

/// 释义去重时的 Jaccard 字符集相似度阈值。
///
/// 达到该值视为重复释义，保留文本更长（更详细）的一条。
/// 来源：旧版 `dictionary/merge.ts` 的 `deduplicateSimilarDefinitions`。
const double definitionDuplicateThreshold = 0.72;

/// 判断「句子」而非「短语」时的最少词数（配合句末标点等条件使用）。
const int sentenceMinTokens = 7;

/// 含从句特征的句子所需最少词数。
const int sentenceClauseMinTokens = 3;

/// 含限定动词的句子所需最少词数。
const int sentenceFiniteVerbMinTokens = 4;

// ═══════════════════════════════════════════════════════════════
// FSRS 间隔重复（对应旧版 modules/reviews/fsrs.ts）
// ═══════════════════════════════════════════════════════════════

/// FSRS 遗忘曲线衰减系数：R(S) = 1 / (1 + 1/9) = 0.90。
const double fsrsDecayFactor = 1 / 9;

/// 目标记忆保持率下限。
const double minRetentionRate = 0.7;

/// 目标记忆保持率上限。
const double maxRetentionRate = 0.99;

/// 默认目标记忆保持率。
const double defaultRetentionRate = 0.9;

/// FSRS 最大复习间隔（天）。
const int fsrsMaximumIntervalDays = 3650;

/// FSRS 内部状态序号：新卡（对应 `ts-fsrs` 的 `State.New`）。
///
/// Dart 版 `package:fsrs` 的 `State` 枚举**没有** `New` 取值
/// （只有 learning/review/relearning），但 `review_cards.fsrs_state`
/// 沿用旧版 0–3 的序号，备份回放要逐字段比对卡片快照，所以这个 0 必须具名。
/// 约定：`fsrsState == fsrsStateNew` ⟺ 学习态且从未复习过。
const int fsrsStateNew = 0;

/// FSRS 内部状态序号：学习态。
const int fsrsStateLearning = 1;

/// FSRS 内部状态序号：复习态。
const int fsrsStateReview = 2;

/// FSRS 内部状态序号：重学态。
const int fsrsStateRelearning = 3;

/// 可提取性（retrievability）的下限。
const double retrievabilityFloor = 0.05;

/// 可提取性的上限。
const double retrievabilityCeiling = 1;

/// 保持率乘数下限——记忆再模糊也保留三成得分，避免熟练度断崖。
const double retentionMultiplierFloor = 0.3;

// ═══════════════════════════════════════════════════════════════
// 熟练度评分（对应旧版 modules/reviews/mastery.ts）
// ═══════════════════════════════════════════════════════════════

/// 熟练度各分项权重（满分 100，罚分另减）。
///
/// 旧版用 `MASTERY_WEIGHTS` 对象；此处拆成具名常量以便单测引用。
/// 熟练度分项权重：FSRS 稳定性。
const int masteryWeightStability = 30;

/// 熟练度分项权重：历史正确率。
const int masteryWeightAccuracy = 25;

/// 熟练度分项权重：当前排期间隔长度。
const int masteryWeightInterval = 18;

/// 熟练度分项权重：连续正确次数。
const int masteryWeightStreak = 10;

/// 熟练度分项权重：累计复习次数。
const int masteryWeightExperience = 7;

/// 熟练度分项权重：作答速度加成。
const int masteryWeightSpeed = 10;

/// 罚分上限，避免负分无限下探。
const int masteryPenaltyCap = 25;

/// 熟练度「近期 AGAIN」统计窗口：30 天。
const int masteryWindowMs = 30 * dayMs;

/// 表现统计窗口（近 14 天答错 / 模糊 / AGAIN）：14 天。
const int performanceWindowMs = 14 * dayMs;

/// 稳定性归一化分母（天）。
const double masteryStabilityFullDays = 365;

/// 间隔归一化分母（天）。
const double masteryIntervalFullDays = 90;

/// 连续正确归一化分母（次）。
const double masteryStreakFullCount = 5;

/// 经验（复习次数）归一化分母（次）。
const double masteryExperienceFullReps = 20;

/// 速度基准（毫秒）——低于此值给满分速度加成。
const double masterySpeedBaselineMs = 15000;

/// 单次遗忘（lapse）扣分。
const int masteryPenaltyPerLapse = 3;

/// 近期 AGAIN 每次扣分。
const int masteryPenaltyPerRecentAgain = 2;

/// 处于活跃错词状态的一次性扣分。
const int masteryPenaltyActiveWrongWord = 5;

/// 进入 FAMILIAR 及以上所需最少复习次数。
const int masteryMinReps = 3;

/// 进入 FAMILIAR 及以上所需最少已排期间隔（天）。
const int masteryMinScheduledDays = 7;

/// LEARNING 的分数下限。
const int masteryLearningScore = 40;

/// FAMILIAR 的分数下限。
const int masteryFamiliarScore = 45;

/// PROFICIENT 的分数下限。
const int masteryProficientScore = 70;

/// MASTERED 的分数下限。
const int masteryMasteredScore = 85;

/// PROFICIENT 所需最少间隔（天）。
const int masteryProficientDays = 30;

/// MASTERED 所需最少间隔（天）。
const int masteryMasteredDays = 90;

/// FAMILIAR 所需最低正确率。
const double masteryFamiliarAccuracy = 0.7;

/// PROFICIENT 所需最低正确率。
const double masteryProficientAccuracy = 0.8;

/// MASTERED 所需最低正确率。
const double masteryMasteredAccuracy = 0.9;

// ═══════════════════════════════════════════════════════════════
// 判题容错（对应旧版 modules/reviews/answer-evaluation.ts）
// ═══════════════════════════════════════════════════════════════

/// 允许「单字母手误」的目标词最短长度。
///
/// 短词容错会误判（cat/cut），故仅对长词放宽。
const int spellingFuzzyMinLength = 7;

/// 允许的最大编辑距离。
const int spellingFuzzyMaxDistance = 1;

/// 句子判分启用编辑距离容错的最短长度。
///
/// 短句容错会误判，故仅对长句放宽。
const int sentenceFuzzyMinLength = 20;

/// 句子判分允许的编辑距离占期望答案长度的比例。
const double sentenceFuzzyRatio = 0.08;

/// 句子判分允许的最小编辑距离。
///
/// 比例算出的距离可能为 0，但既然已超过 [sentenceFuzzyMinLength]，
/// 至少容忍 1 个字符的手误。
const int sentenceFuzzyMinDistance = 1;

/// 释义题选项总数（1 个正确项 + 干扰项）。
const int meaningChoiceCount = 4;

/// 释义题需要的干扰项数量。
const int meaningDistractorCount = meaningChoiceCount - 1;

// ═══════════════════════════════════════════════════════════════
// 错词本（对应旧版 modules/reviews/wrong-state.ts 与 background/maintenance.ts）
// ═══════════════════════════════════════════════════════════════

/// 解除错词所需的连续正确天数。
const int wrongWordResolveConsecutiveDays = 3;

/// 解除错词所需的、距上次答错的最少自然日间隔。
///
/// 与上一条共同作用，防止同一天刷题快速解除。
const int wrongWordResolveMinDayGap = 2;

/// 错词自动衰减天数——超过该天数未再答错则退出错词本。
const int wrongWordDecayDays = 30;

// ═══════════════════════════════════════════════════════════════
// 题型选择（对应旧版 modules/study/question-type-config.ts 与 lib/config.ts）
// ═══════════════════════════════════════════════════════════════

/// 题型默认权重。
const int defaultQuestionTypeWeight = 5;

/// 题型权重下限。
const int minQuestionTypeWeight = 1;

/// 题型权重上限。
const int maxQuestionTypeWeight = 10;

/// 加权随机时的权重下限，避免除零。
const double questionTypeWeightFloor = 0.001;

/// 加权随机取值上限，避免 `cursor` 恰好落在边界外。
const double questionTypeRandomCeiling = 0.999999;

/// 权重占比换算成百分数的基数。
///
/// 命名带 `questionType` 前缀：`data/dictionary/dictionary_constants.dart` 已有一个
/// 同值的 `percentScale`，而同时 import 两个文件的 `services/` 会在重名上报错。
const int questionTypePercentScale = 100;

// 题型权重预设：对应旧版
// `src/app/(main)/settings/components/question-type-settings.tsx:31-36` 的 `PRESETS`。
// 旧版把权重直接写在组件字面量里；本版按「数值常量唯一出处」的约定逐条具名，
// 便于与旧版逐行对照，也便于单测钉住「预设到底设了哪些权重」。
// 「记忆为主」里的英译中（自评）沿用 [defaultQuestionTypeWeight]，不再单列常量。

/// 预设「记忆为主」给英译中（选择）的权重。
const int recallFirstChoiceWeight = 8;

/// 预设「拼写强化」给字母拼词的权重。
const int spellingFocusLetterBankWeight = 8;

/// 预设「记忆为主」给中译英（选择）的权重。
const int recallFirstTranslateWeight = 7;

/// 预设「拼写强化」给例句填空的权重。
const int spellingFocusClozeWeight = 7;

/// 预设「拼写强化」给中译英（拼写）的权重。
const int spellingFocusSpellWeight = 9;

/// 预设「听力强化」给两种听力题型的权重。
const int listeningFocusWeight = 9;

/// 预设「记忆为主」给中译英（拼写）的权重。
///
/// 刻意压到最低：这一档的主张是「先用选择题认词，再用拼写输出」，
/// 拼写题在认词之前出现只会制造挫败感。
const int recallFirstSpellingWeight = 4;

/// `LETTER_BANK` 题型适用的词条模式：3–14 个纯字母。
const String letterBankTermPattern = r'^[a-zA-Z]{3,14}$';

/// 听力题中「熟练分低于此值时改用选择题」的阈值。
///
/// 拼写太难会打击信心，先降低作答门槛。
const int listeningWeakMasteryScore = 50;

/// 听力题中按此间隔插入一道选择题（其余为拼写题）。
const int listeningChoiceEvery = 2;

/// 听力题中「弱项」判定使用的取模基数。
const int listeningWeakMasteryEvery = 3;

/// 听力题中「弱项」判定使用的余数。
const int listeningWeakMasteryOffset = 1;

/// 拼写类学习中按此间隔插入一道字母拼图。
const int spellingLetterBankEvery = 3;

/// 每日学习中「熟练分低于此值只用选择题」的阈值。
const int dailyLowMasteryScore = 35;

/// 每日学习中「熟练分低于此值且例句可用时改用填空题」的阈值。
const int dailyMediumMasteryScore = 55;

/// 每日学习中「熟练分低于此值改用看汉选英」的阈值。
const int dailyHighMasteryScore = 70;

/// 每日学习中按此间隔插入一道字母拼图。
const int dailyLetterBankEvery = 4;

/// 每日学习中字母拼图插入位置的余数。
const int dailyLetterBankOffset = 3;

/// 每日学习中按此间隔插入一道填空题。
const int dailyClozeEvery = 6;

/// 每日学习中填空题插入位置的余数。
const int dailyClozeOffset = 5;

// ═══════════════════════════════════════════════════════════════
// 每日学习队列（对应旧版 modules/study/candidates.ts 与 study/plan.ts）
// ═══════════════════════════════════════════════════════════════

/// 跳过（稍后再学）后的冷却时长。
const int skipCooldownMs = 12 * hourMs;

/// `study_session_items.skip_reason`：因词条被暂停而撤下的题目。
///
/// **必须与旧版逐字符一致**：跳过原因参与候选排除判断
/// （`SESSION_EXPIRED` / `PROGRESS_RESET` 属系统收尾，不算用户意愿，
/// 见 `study_dao.dart` 的 `_availabilitySql`），备份回放与跨端统计也按
/// 该字符串分组，改字面量等于让旧数据与新数据对不上。
const String wordSuspendedSkipReason = 'WORD_SUSPENDED';

/// 学习会话可恢复的有效期。
const int sessionResumeTtlMs = dayMs;

/// 备份文件的大小上限（字节）。
///
/// 与旧版 `src/modules/backups/service.ts:60` 的 100 MB 一致。
/// 真实备份约 27 MB；上限只用来挡住误选了一个超大文件时的 OOM，
/// 不限制正常用户的词库规模。
const int maxBackupBytes = 100 * 1024 * 1024;

/// 到期排序中「逾期天数」的封顶值，防止陈年旧卡长期霸榜。
const double dueOverdueCapDays = 10;

/// 到期排序中 FSRS 难度的加权系数。
const double dueDifficultyWeight = 0.15;

/// 到期排序中近 14 天答错次数的加权系数。
const double dueRecentWrongWeight = 1.2;

/// 到期排序中近 14 天 AGAIN 次数的加权系数。
const double dueRecentAgainWeight = 0.8;

/// 到期排序中近 14 天 HARD 次数的加权系数。
const double dueRecentHardWeight = 0.35;

/// 每日新词占配额的比例。
const double dailyNewWordRatio = 1 / 3;

/// 配额补足时的宽限比例——避免为凑满额度引入质量过差的候选。
const double dailyQuotaGraceRatio = 0.2;

/// 交错组队时向前预看的候选数量。
const int categoryLookahead = 6;

/// 混合抽题时错词相对到期复习的权重加成。
///
/// 错词是用户已经暴露的薄弱点，同等数量下应比普通到期卡更早出现。
const double wrongCandidateWeightBonus = 1.25;

/// 加权抽题时单项权重下限，避免除零。
const double candidateWeightFloor = 0.001;

/// 加权抽题取值上限，避免 `cursor` 恰好落在边界外。
const double candidateRandomCeiling = 0.999999;

/// 候选池下标：到期复习。
const int poolIndexDue = 0;

/// 候选池下标：错词。
const int poolIndexWrong = 1;

/// 候选池下标：新词。
const int poolIndexFresh = 2;

/// 交错组队配比 [到期, 错词, 新词]：听力模式。
const List<int> interleaveRatioListening = <int>[5, 2, 2];

/// 交错组队配比 [到期, 错词, 新词]：拼写模式。
const List<int> interleaveRatioSpelling = <int>[5, 3, 1];

/// 交错组队配比 [到期, 错词, 新词]：默认（句子复习）。
const List<int> interleaveRatioDefault = <int>[4, 2, 1];

/// 预估单题耗时（秒）：复习题。
const int estimatedSecondsPerReview = 35;

/// 预估单题耗时（秒）：错词题。
const int estimatedSecondsPerWrong = 55;

/// 预估单题耗时（秒）：新词题。
const int estimatedSecondsPerNew = 70;

/// 连续学习时，每日队列抽空后一次补齐的题量。
///
/// 不设太大：补题是为了「点进来别只有 2 道题」，而不是把新词全部塞给用户。
const int continuousBatchSize = 10;

/// 每日默认新词配额。
const int defaultDailyNewWords = 10;

/// 每日默认错词配额。
const int defaultDailyWrongWordLimit = 10;

/// 每日默认到期复习配额。
const int defaultDailyDueReviewLimit = 30;

/// 每日新词配额上限。
const int maxDailyNewWords = 100;

/// 每日错词配额上限。
const int maxDailyWrongWordLimit = 100;

/// 每日到期复习配额上限。
const int maxDailyDueReviewLimit = 500;

// ═══════════════════════════════════════════════════════════════
// 自适应插题（对应旧版 modules/study/adaptive.ts）
// ═══════════════════════════════════════════════════════════════

/// 同一词条在单次会话内最多插入的追问题数。
const int maxFollowUpsPerWord = 2;

/// 首次答错后，隔多少题复现（拯救工作记忆）。
const int firstFollowUpDelay = 5;

/// 二次答错后，隔多少题复现（加深长时记忆）。
const int secondFollowUpDelay = 10;

/// 自适应插题时，在相邻两项之间取位置的插值比例（0.5 = 中点）。
///
/// `position` 是浮点且带 `(study_session_id, position)` 唯一索引。
/// 反复在同一间隙取中点会逼近浮点精度极限，因此插入前必须校验
/// 插值结果严格落在两端点之间，否则退化为追加到队尾。
const double sessionItemPositionStep = 0.5;

/// 自适应插题追加到队尾时的位置步长。
const double sessionItemAppendStep = 1;

// ═══════════════════════════════════════════════════════════════
// 干扰项与题目构造（对应旧版 modules/study/view.ts）
// ═══════════════════════════════════════════════════════════════

/// 全局干扰项池的容量。
///
/// 旧版每题都跑一次 `ORDER BY RANDOM()`，题量大时是全表扫描。
/// 改为按批取池、池内消费。
const int distractorPoolSize = 80;

/// 每次从全局池中取出的候选数量（含大量重复释义，需要多取）。
const int distractorTakeSize = 12;

/// 从「易混词」中取干扰项时的查询上限。
const int specificDistractorLimit = 6;

/// 从「活跃错词」中取干扰项时的查询上限。
const int activeWrongDistractorLimit = 8;

/// 填空题的占位符。
const String clozeBlankToken = '____';

/// 答案文本的分隔符（多条释义并列）。
const String definitionSeparator = '；';

// ═══════════════════════════════════════════════════════════════
// 学习计时（对应旧版 modules/reviews/duration.ts）
// ═══════════════════════════════════════════════════════════════

/// 单题计入「有效学习时长」的上限。
///
/// 超过此值视为挂机，按上限计——否则统计页的时长会被离屏页面污染。
const int maxActiveAnswerDurationMs = 10 * minuteMs;

// ═══════════════════════════════════════════════════════════════
// CSV 导入（对应旧版 lib/config.ts 与 app/api/imports/preview/route.ts）
// ═══════════════════════════════════════════════════════════════

/// CSV 文件大小上限（10 MiB）。
const int maxCsvBytes = 10 * 1024 * 1024;

/// CSV 行数上限。
const int maxCsvRows = 20000;

/// 导入预览的有效期。
const int importPreviewTtlMs = 30 * minuteMs;

/// 未提交的导入批次过期时长。
///
/// 导入批次停在 `PENDING` 说明中途崩了或进程被杀；
/// 不回收的话撤销按钮会永远停在那里，所以后台按此阈值置为 `FAILED`
/// （对应旧版 `expireStaleBatches`）。
const int importBatchExpiryMs = dayMs;

/// 撤销导入时回显的受阻词条上限。
const int rollbackBlockedTermLimit = 30;

/// 导入历史一次展示的批次数。
const int recentImportBatchLimit = 20;

/// 导入批次行明细的分页大小。
const int importRowPageSize = 50;

/// 导入预览表格最多渲染的行数。
///
/// 两万行全渲染会让首帧卡住数秒；预览的目的是「确认列映射对不对」，
/// 前若干行足够。
const int importPreviewDisplayLimit = 200;

// ═══════════════════════════════════════════════════════════════
// 文章导入（对应旧版 lib/config.ts 与 modules/article-import/extract.ts）
// ═══════════════════════════════════════════════════════════════

/// 文章最短字符数。
const int minArticleChars = 20;

/// 文章最长字符数。
const int maxArticleChars = 50000;

/// 送交 AI 的文章片段字符数。
const int articleSnippetChars = 8000;

/// 分段目标字符数。
const int articleSegmentTargetChars = 2200;

/// 分段硬上限字符数。
const int articleSegmentMaxChars = 4000;

/// 尾段合并阈值——末段短于此值时并入前一段。
const int articleTailMergeThreshold = 60;

/// 最大分段数。
const int maxArticleSegments = 20;

/// 每批最大分段数。
const int maxArticleSegmentsPerBatch = 10;

/// 分段并发数。
const int articleSegmentConcurrency = 3;

/// 分段预览字符数。
const int articleSegmentPreviewChars = 120;

/// 单词候选上限。
const int maxArticleCandidates = 200;

/// 送交 AI 的候选词上限。
const int articleAiCandidateLimit = 80;

/// 短语上限。
const int articlePhraseLimit = 15;

/// 句子上限。
const int articleSentenceLimit = 10;

/// AI 选词的最大输出 token。
const int articleAiMaxOutputTokens = 4500;

/// 句子候选的最短字符数。
const int articleSentenceMinChars = 12;

/// 本地回退推荐词的默认数量上限。
const int articleDefaultRecommendedLimit = 20;

// ═══════════════════════════════════════════════════════════════
// 词条初始化队列（对应旧版 modules/initialization/worker.ts 等）
// ═══════════════════════════════════════════════════════════════

/// 任务重试退避序列（毫秒）：5s → 30s → 2min → 10min → 30min。
///
/// 超出序列长度时使用最后一项。
const List<int> retryBackoffMs = <int>[
  5 * secondMs,
  30 * secondMs,
  2 * minuteMs,
  10 * minuteMs,
  30 * minuteMs,
];

/// 任务最大尝试次数上限（设置项换算后的封顶）。
const int maxAttemptsCeiling = 6;

/// 任务最大尝试次数的下限。
const int maxAttemptsFloor = 1;

/// CSV 导入入队时的固定最大尝试次数。
///
/// 注意：旧版此处硬编码 5，与设置页算出的值（默认 2）不一致，属历史遗留。
/// 本版统一由设置推导，此常量仅用于导入路径的显式覆盖。
const int importJobMaxAttempts = 5;

/// 失败任务的自动重试冷却时长。
const int failedRetryCooldownMs = hourMs;

/// RUNNING 任务视为「锁已失效」的阈值。
///
/// 旧版为 10 分钟；本版为单进程，启动时会全量重置 RUNNING，
/// 该阈值仅用于会话中途的异常兜底。
const int workerStaleAfterMs = 10 * minuteMs;

/// 单批处理的任务数上限。
const int defaultMaxJobsPerTick = 3;

/// 周期性维护的执行间隔（队列已排空后的保活间隔）。
const int maintenanceIntervalMs = 10 * minuteMs;

/// 上一批有产出时的维护间隔。
///
/// 有活就尽快推完，10 分钟只适用于「没有待处理任务」的保活。
/// 取 30s 而非旧版的 3s：本地一次 tick 要真联网查词典，
/// 按 3s 节奏排期会持续占着数据通道，对耗电没有好处。
const int maintenanceBusyIntervalMs = 30 * secondMs;

/// 每日 AI 建议的生成时刻（本地时区，24 小时制）。
const int dailySuggestionHour = 0;

/// 每日 AI 建议的生成分钟。
const int dailySuggestionMinute = 5;

/// AI 内容质量分低于此值时整份丢弃。
///
/// 来源：旧版 `dictionary/providers/ai-lexical.ts`。
const int aiQualityScoreThreshold = 45;

/// PRIORITY_FALLBACK 策略下，内容质量达到此值时提前终止 provider 循环。
const double providerFallbackQualityThreshold = 0.8;

/// 初始化任务优先级：新建词条。
const int jobPriorityNewWord = 10;

/// 初始化任务优先级：补充缺失字段的已有词条。
const int jobPriorityFillMissing = 30;

/// 初始化任务优先级：强制覆盖的已有词条。
const int jobPriorityForceOverwrite = 60;

/// 初始化任务优先级：补充任务（助记、例句翻译）。
const int jobPrioritySupplemental = 20;

/// 初始化任务优先级：手动批量初始化。
const int jobPriorityManualBulk = 90;

/// 初始化任务优先级：默认（单条手动触发）。
const int jobPriorityDefault = 100;

/// 初始化预览展示的示例词条条数。
///
/// 沿用旧版 `/api/initialization/preview` 的 8 条：够认出「这是我要补的那
/// 一批」，再多只会把侧栏撑成一堵墙。
const int initializationPreviewSampleLimit = 8;

/// 初始化预览展示的跳过明细条数。
///
/// 跳过原因只有两类（已满足 / 已暂停），逐条列出来最多也就十几行；
/// 上限是为了让「暂停了 800 个词条」这种情况不至于刷屏。
const int initializationPreviewSkipLimit = 12;

/// 单次 SQL 的绑定参数上限保护——批量操作按此分批。
///
/// SQLite 默认变量上限为 999（旧版）或 32766（新版），
/// 取保守值以免在低版本设备上失败。
const int sqlBatchChunkSize = 500;

// ═══════════════════════════════════════════════════════════════
// LLM 调用（对应旧版 modules/llm/client.ts）
// ═══════════════════════════════════════════════════════════════

/// LLM 默认最大输出 token。
const int defaultLlmMaxOutputTokens = 2000;

/// LLM 默认温度。
const double defaultLlmTemperature = 0.2;

/// LLM 默认超时（毫秒）。
const int defaultLlmTimeoutMs = 180 * secondMs;

/// LLM 超时下限（毫秒）。
const int minLlmTimeoutMs = 5 * secondMs;

/// LLM 超时上限（毫秒）。
const int maxLlmTimeoutMs = 300 * secondMs;

/// 思考预算下限（token）。
const int minThinkingBudgetTokens = 1024;

/// 思考预算上限（token）。
const int maxThinkingBudgetTokens = 20000;

/// 思考预算默认值（token）。
const int defaultThinkingBudgetTokens = 4000;

/// 判定为「瞬时错误」的 HTTP 状态码。
///
/// 只有瞬时错误才切换备用模型；鉴权与格式错误切换无意义。
const Set<int> transientHttpStatusCodes = <int>{408, 409, 429};

/// 瞬时错误的 HTTP 状态码下界（5xx）。
const int transientServerErrorFloor = 500;

/// AI 重试遍数下限。
///
/// 来源：旧版 `modules/settings/service.ts:77` 的 `.min(0)`。
/// 0 与 1 在当前实现下等价——`LlmConfig` 会把候选链遍数夹到至少 1 遍。
///
/// **为什么叫 Floor/Ceiling/Default 而不是 `minAiRetryCount` /
/// `defaultAiRetryCount`**：`lib/data/dictionary/dictionary_constants.dart`
/// 已经占了后两个名字，而 `lib/services/llm/llm_config.dart` 同时 import
/// 这两个文件，同名会让引用产生歧义。两组常量取值必须一致，
/// 由 `test/domain/models/app_settings_test.dart` 断言。
const int aiRetryCountFloor = 0;

/// AI 重试遍数上限。
///
/// 来源：旧版 `modules/settings/service.ts:77` 的 `.max(5)`。
const int aiRetryCountCeiling = 5;

/// AI 重试遍数默认值。
///
/// 来源：旧版 `lib/config.ts` 的 `aiRetryCount: 1`，即候选链只跑一遍不重放。
const int aiRetryCountDefault = 1;

// ═══════════════════════════════════════════════════════════════
// 词典 provider（对应旧版各 provider 实现）
// ═══════════════════════════════════════════════════════════════

/// 词典类 provider 的超时（毫秒）。
const int dictionaryProviderTimeoutMs = 10 * secondMs;

/// 翻译类 provider 的超时（毫秒）。
const int translationProviderTimeoutMs = 8 * secondMs;

/// 拉取模型列表的超时（毫秒）。
const int modelListTimeoutMs = 15 * secondMs;

/// 有道双端点重试的随机抖动下界（毫秒）。
const int youdaoRetryJitterMinMs = 120;

/// 有道双端点重试的随机抖动上界（毫秒）。
const int youdaoRetryJitterMaxMs = 400;

/// 音频缓存条目上限。
///
/// 旧版服务端内存 LRU 为 200 条；本版落盘缓存，此处保留作为软上限。
const int ttsCacheMaxEntries = 200;

/// TTS 合成超时（毫秒）。
const int ttsTimeoutMs = 15 * secondMs;

// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// 统计页（对应旧版 app/(main)/statistics/page.tsx）
// ═══════════════════════════════════════════════════════════════

/// 趋势图默认展示的天数。
const int defaultTrendDays = 30;

/// 趋势图可选的天数档位。
const List<int> trendDayOptions = <int>[7, 14, 30, 90];

/// 迷你趋势条展示的最近作答次数。
const int recentResultsLimit = 20;

/// 统计页「学习时长」的分钟换算基数。
const int statsMinutesPerHour = 60;

/// 词条详情页「复习历史」展示的条数上限。
const int reviewHistoryLimit = 20;

// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// 词库列表页（对应旧版 app/(main)/words/page.tsx）
// ═══════════════════════════════════════════════════════════════

/// 词库列表每页条数。
///
/// 与旧版 `page.tsx` 请求里的 `limit: "40"` 一致。放在这里而不是
/// `features/words`：DAO 的 `WordQuery` 默认值与界面上的分页条是同一个数，
/// 分成两处迟早会对不上（旧版就是请求与分页控件各写一份 40）。
const int wordListPageSize = 40;

// 界面交互（对应旧版 lib/config.ts 与各组件内联值）
// ═══════════════════════════════════════════════════════════════

/// 选择题揭示答案前的默认延迟（秒）。
const int defaultChoiceRevealDelaySeconds = 2;

/// 选择题揭示答案延迟的上限（秒）。
const int maxChoiceRevealDelaySeconds = 60;

/// 语音朗读语速下限。
const double minSpeechRate = 0.5;

/// 语音朗读语速上限。
const double maxSpeechRate = 2;

/// 侧边栏布局的启用宽度断点。
///
/// 与旧版 Tailwind 的 `lg:` 断点一致：≥1024 逻辑像素走侧边栏，
/// 否则降级为底部 Tab Bar。
const double sidebarBreakpoint = 1024;

/// 侧边栏宽度。
const double sidebarWidth = 256;

/// 侧边栏占据的主内容左边距（含间隙）。
const double sidebarContentInset = 264;

/// 桌面窗口默认宽度。
const double defaultWindowWidth = 1280;

/// 桌面窗口默认高度。
const double defaultWindowHeight = 840;

/// 桌面窗口最小宽度——设得比侧边栏断点小，允许用户缩到「底部 Tab」形态。
const double minWindowWidth = 720;

/// 桌面窗口最小高度。
const double minWindowHeight = 560;

/// 默认发音口音。
const String defaultAccent = 'US';

/// 默认语速。
const double defaultSpeechRate = 1;

// ═══════════════════════════════════════════════════════════════
// 词条详情页的写操作（对应旧版 modules/words/mutations.ts）
// ═══════════════════════════════════════════════════════════════

/// 用户手工撰写的那条释义的 `definitions_json[].source`。
///
/// **必须与旧版逐字符一致**：`updateManualDefinition` 按「来源 + 已编辑」
/// 两个标记识别历史手工释义并整体替换，改字面量会让旧备份里的手工释义
/// 永远删不掉，从而每次保存都多一条。
const String userAuthoredDefinitionSource = 'user';

/// 手工释义的长度上限（字符）。
///
/// 与旧版 `modules/words/mutations.ts` 的 `manualDefinitionSchema` 一致：
/// 释义是要进选择题选项的，超长条目既撑破卡片也会让出题失去意义。
const int manualDefinitionMaxLength = 2000;

/// 手工释义的词性标注长度上限（字符）。
const int manualDefinitionPartOfSpeechMaxLength = 50;

/// 「初始化质量」卡展示的数据源调用记录条数上限。
///
/// 一个词条在多次重试下可能积累上百条调用记录，卡片是排查工具而不是流水账；
/// 默认按时间倒序取最近这些条，够定位「是哪一次调用出的问题」。
const int providerAttemptCardLimit = 50;
