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
/// 命名带 `questionType` 前缀：`percentScale` 这个名字已经被「百分数换算
/// 基数」占用，而两者语义不同——前者是题型权重占比，后者是通用百分比。
/// 分开命名比共用一个更容易在改动时看清影响面。
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

// ═══════════════════════════════════════════════════════════════
// 远程备份（WebDAV）
// ═══════════════════════════════════════════════════════════════

/// WebDAV 的普通请求超时（PROPFIND / MKCOL / 小文件 GET）。
///
/// 比词典数据源的 10 秒宽：WebDAV 常跑在自建 NAS 上，
/// 建目录与列目录都可能比公网 API 慢。
const int webdavRequestTimeoutMs = 30 * secondMs;

/// WebDAV 上传备份的超时。
///
/// 真实备份约 27 MB，移动网络下要留足时间；超时后由用户重试，
/// 不做断点续传（本版不支持，见 `docs/REMOTE_BACKUP.md`）。
const int webdavUploadTimeoutMs = 5 * minuteMs;

/// 自动备份的检查节奏。
///
/// 定时器按它醒来判断「周期到了没有、数据变了没有」，**不**代表备份周期：
/// 备份周期由用户配置（[defaultWebdavAutoIntervalMinutes] 等）。
/// 取 5 分钟而不是 1 分钟：自动备份是后台行为，没必要每分钟查一次库。
const int webdavAutoCheckIntervalMs = 5 * minuteMs;

/// 自动备份的默认周期（一天）。
const int defaultWebdavAutoIntervalMinutes = 24 * 60;

/// 自动备份周期可选项（分钟）；`0` 表示关闭自动备份。
const List<int> webdavAutoIntervalOptions = <int>[
  0,
  6 * 60,
  24 * 60,
  3 * 24 * 60,
  7 * 24 * 60,
];

/// 远端列表一次最多展示的备份条数。
///
/// 列表只用于「选一份恢复」，把目录里积累的上百份备份全画出来没有意义。
const int webdavMaxListedBackups = 20;

// ═══════════════════════════════════════════════════════════════
// 局域网同步
//
// 语义见 `docs/LAN_SYNC.md`：一台设备开共享（只读 HTTP 服务端），
// 同网段的另一台发现它、输配对码、拉取并全量替换本地数据。
// ═══════════════════════════════════════════════════════════════

/// 共享服务端默认监听的 TCP 端口。
///
/// 用户可在设置里改：8765 被别的程序占用时，换一个端口比让用户去关掉
/// 那个程序容易得多。取值要求见 [lanSyncMinPort] / [lanSyncMaxPort]。
const int lanSyncDefaultPort = 8765;

/// 发现应答器监听的 UDP 端口（固定，用户不可改）。
///
/// 与 TCP 端口分开是有意的：发现只是「敲门」，能改它只会多一处
/// 两台设备对不上的地方。真正的连接与鉴权都发生在 [lanSyncDefaultPort] 上。
const int lanSyncDiscoveryPort = 8766;

/// 局域网同步的协议版本。
///
/// 握手与发现报文都带它；两端不一致时明确报「版本不兼容」，
/// 而不是让一台旧版设备用错误的字段解读新版的回复。
const int lanSyncProtocolVersion = 1;

/// 配对码的位数。
///
/// 6 位数字（10^6 种）配「连续错码即停共享」的限流：既要能在主机屏幕上
/// 一眼读出来手动输入，又不能让同网段的人靠穷举拿到数据。
const int lanSyncPairingCodeLength = 6;

/// 连续多少次配对码错误后自动停止共享。
///
/// 这是限流而不是锁定：停掉之后用户重新开启共享会拿到一个新码，
/// 合法用户可以立刻恢复，而穷举者每次都要让受害者重新操作一次。
const int lanSyncPairingCodeMaxAttempts = 10;

/// 配对码生成时使用的数字字符集。
const String lanSyncPairingCodeAlphabet = '0123456789';

/// 共享会话标识的字符集与长度。
///
/// 与配对码分开：配对码要人能念出来（纯数字、6 位），会话标识只要不重复
/// （十六进制、16 位），用它把「本机自己的广播应答」从搜索结果里滤掉。
const String lanSyncInstanceIdAlphabet = '0123456789abcdef';

/// 见 [lanSyncInstanceIdAlphabet]。
///
/// 16 位十六进制 = 64 位随机量，碰撞概率低到不必去查重。
const int lanSyncInstanceIdLength = 16;

/// 局域网同步的服务标识。
///
/// 同时出现在 UDP 发现报文与 HTTP 握手响应里，因此放在常量层而不是
/// 协议文件里：`lib/domain` 的发现结果模型也要用它编解码报文，
/// 而 domain 不能反向依赖 data 层。
const String lanSyncServiceName = 'lexiloop-lan-sync';

/// 发现报文里的「有人在吗」。
const String lanSyncDiscoveryQueryKind = 'query';

/// 发现报文里的「我在」。
const String lanSyncDiscoveryReplyKind = 'reply';

/// 「未指定地址」的字符串形态。
///
/// 同一台机器上向广播地址发包时，内核有时会把数据报的来源地址留成它。
/// 它永远连不上，因此既不能当成一台设备，也不能拿来回应答。
const String lanSyncUnspecifiedAddress = '0.0.0.0';

/// 握手 / 小请求的超时。
const int lanSyncRequestTimeoutMs = 30 * secondMs;

/// 拉取备份的超时。
///
/// 与 WebDAV 上传同一量级：局域网上 27MB 通常一两秒，
/// 留足余量是为了容忍老旧的 2.4G Wi-Fi 与低端手机。
const int lanSyncTransferTimeoutMs = 5 * minuteMs;

/// 一次「搜索设备」等待应答的时长。
///
/// 取 3 秒：UDP 广播在局域网上的往返是毫秒级，剩下的时间全都花在
/// 对端被系统调度起来处理报文上。再长只会让用户对着转圈等。
const int lanSyncDiscoveryTimeoutMs = 3 * secondMs;

/// 发现结果一次最多展示多少台设备。
///
/// 与 [webdavMaxListedBackups] 同理：这是「选一台来同步」，
/// 一个宿舍或办公室网段里可能有几十台设备在应答。
const int lanSyncMaxListedHosts = 10;

/// 端口可配置区间的下界（避开特权端口）。
const int lanSyncMinPort = 1024;

/// 端口可配置区间的上界。
const int lanSyncMaxPort = 65535;

/// 2xx 的下界（含）。
const int lanSyncStatusSuccessFloor = 200;

/// 2xx 的上界（不含）。
const int lanSyncStatusSuccessCeil = 300;

/// 配对码不正确。
const int lanSyncStatusUnauthorized = 401;

/// 目标路径不存在（对方已经停止共享）。
const int lanSyncStatusNotFound = 404;

/// 冲突（同一时刻已有一次同步在进行）。
const int lanSyncStatusConflict = 409;

/// 备份超过大小上限。
///
/// 与「服务端出错」分开：超限是一个稳定的、可解释的结果（对方的词库太大，
/// 换多少次都一样），报「稍后重试」只会让用户白试。
const int lanSyncStatusTooLarge = 413;

/// 服务端错误的起点。
const int lanSyncStatusServerErrorFloor = 500;

// ── IPv4 字面量校验（局域网发现的地址合法性） ──

/// 一个 IPv4 地址按 `.` 分成的段数。
const int ipv4PartCount = 4;

/// 单个 IPv4 段的最大字符数（`255` 是三位）。
const int ipv4PartMaxDigits = 3;

/// 单个 IPv4 段的最大数值。
const int ipv4OctetMax = 255;

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

/// 一次翻译任务最多送出多少条缺失内容。
///
/// 与旧版 `modules/translations/service.ts` 的 `translateMissingDefinitions`
/// 一致（`source.slice(0, 20)`）：一个词条可能有十几条源语言释义，
/// 一次全送会把单次请求撑到超时上限，而分批推进对用户是可见的进度。
const int translationBatchLimit = 20;

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
/// 取 5s：导入文章分词后的 30–50 个词可在 ~1 分钟内由有道补全完毕；
/// 应用切后台时由 `MaintenanceBootstrap` 暂停调度，不产生后台耗电。
const int maintenanceBusyIntervalMs = 5 * secondMs;

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

/// 初始化任务优先级：从关联词卡片加入词库。
///
/// 旧版 `modules/words/related.ts` 的 `addRelatedWord` 写死 80：比用户显式
/// 选中的批量初始化（90）低一档、比后台补充任务（20）高得多——用户刚刚
/// 点下「加入词库」，这个任务应当排在其他自动任务前面。
const int jobPriorityRelatedWord = 80;

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

/// 有道直连发音接口允许的最大英文词数。
///
/// 实测 `dict.youdao.com/dictvoice` 对单词和常见 2–5 词短语返回 200 MP3，
/// 对任意完整长句返回 500 JSON；超过该词数直接跳过有道，交给后续引擎。
const int youdaoDirectMaxWords = 6;

/// 学习自动朗读时，若后续还有离线兜底引擎，允许等待在线语音的上限（毫秒）。
///
/// 有道常规耗时约 200ms，该上限既能让首题在正常网络下稳定听到在线真人发音，
/// 又能防止弱网或断网假死时长时间阻塞刷题节奏。
const int autoPlayOnlineTimeoutMs = 2500;

/// AI 重试遍数下限。
///
/// 来源：旧版 `modules/settings/service.ts:77` 的 `.min(0)`。
/// 0 与 1 在当前实现下等价——`LlmConfig` 会把候选链遍数夹到至少 1 遍。
///
/// **为什么叫 Floor/Ceiling 而不是 `minAiRetryCount`**：后者这个名字已经被
/// 「AI 参数」分节里的边界常量占用，而两处语义不同——这里是**设置项的取值
/// 范围**，那里是**LLM 请求参数的边界**。两组常量取值必须一致，
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
/// 旧版服务端内存 LRU 为 200 条；本版升级为 L1 内存 + L2 磁盘二级缓存，
/// 此处控制进程内热缓存容量。
const int ttsCacheMaxEntries = 200;

/// 离线语音磁盘缓存默认容量上限（MB）；`0` 表示不限制。
const int defaultAudioCacheMaxSizeMb = 200;

/// 离线语音磁盘缓存可配置的最大上限（MB）。
const int maxAudioCacheMaxSizeMb = 4096;

/// 设置页提供的离线语音缓存容量上限档位（MB，`0` 表示不限制）。
const List<int> audioCacheMaxSizeOptionsMb = <int>[100, 200, 500, 1024, 0];

/// 每 MB 对应的字节数（用于将设置上限换算为字节）。
const int audioCacheBytesPerMb = 1024 * 1024;

/// 磁盘缓存超限执行 LRU 淘汰时的目标水位比例（回落至 85% 避免频繁扫盘）。
const double audioCacheEvictTargetRatio = 0.85;

/// 普通播报写入磁盘时，每累计写入多少条才检查一次容量上限。
const int audioCacheEvictWriteStride = 20;

/// 词库离线语音批量预缓存的并发连接数。
const int audioPrecacheConcurrency = 3;

/// 批量预缓存两次请求之间的最小抖动间隔（毫秒），对公共发音接口更友好。
const int audioPrecacheJitterMinMs = 60;

/// 批量预缓存两次请求之间的最大抖动间隔（毫秒）。
const int audioPrecacheJitterMaxMs = 140;

/// 预缓存容量预估使用的单条单词音频估算字节数（实测有道 MP3 约 10–12 KB）。
const int audioEstimatedBytesPerWord = 12 * 1024;

/// Flutter Edge 直连建立连接的超时（秒）。
const int directEdgeConnectTimeoutSeconds = 15;

/// Flutter Edge 单次语音合成的整体超时（秒）。
const int directEdgeRequestTimeoutSeconds = 30;

// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// 统计页（对应旧版 app/(main)/statistics/page.tsx）
// ═══════════════════════════════════════════════════════════════

/// 趋势图默认展示的天数。
const int defaultTrendDays = 30;

/// 趋势图可选的天数档位。
///
/// 与旧版 `statistics/page.tsx` 的 `Segmented` 逐档对齐（7 天 / 30 天 / 90 天 /
/// 一年）。**必须与 [statisticsDailyDetailLimit] 一起看**：明细表只列最近
/// 若干天，档位再大也不会把明细撑成无底洞。
const List<int> trendDayOptions = <int>[7, 30, 90, 365];

/// 统计页「最近学习明细」最多列出多少天。
///
/// 旧版明细表固定 `slice(0, 30)`，与趋势档位无关——它是「最近发生了什么」，
/// 不是「这一档的全部」。
const int statisticsDailyDetailLimit = 30;

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
///
/// 这是**倍率**：1 = 正常语速，2 = 两倍速。与具体语音引擎的参数刻度无关，
/// 「倍率 → 引擎参数」的折算在 `services/tts_service.dart` 一处完成。
const double minSpeechRate = 0.5;

/// 语音朗读语速上限。
const double maxSpeechRate = 2;

/// `AVSpeechUtterance.rate`（iOS/macOS）的刻度：正常语速。
///
/// iOS/macOS 的 `rate` 不是倍率——`AVSpeechUtteranceDefaultSpeechRate` 是 0.5，
/// 上限 `AVSpeechUtteranceMaximumSpeechRate` 是 1.0（两者都在
/// `AVSpeechSynthesis.h` 里声明）。把界面的倍率直接下发，默认的 1.0 就顶到了
/// 引擎上限：**默认设置听起来就是最快语速**，滑条再往上拉也毫无变化。
const double avSpeechUtteranceDefaultRate = 0.5;

/// `AVSpeechUtterance.rate` 的可接受区间。
///
/// 与 `AVSpeechUtteranceMinimumSpeechRate` / `AVSpeechUtteranceMaximumSpeechRate`
/// 一一对应，只是写成具名常量，好让 `_engineRate` 统一夹取系数：
/// 界面的 0.5×–2× 折算后落在 0.25–1.0，**整条滑条都在有效区间内**，
/// 不会出现「拉到头却没变化」的死区。
const double minUtteranceRateFactor = 0;

/// 见 [minUtteranceRateFactor]。
const double maxUtteranceRateFactor = 1;

/// 侧边栏布局的启用宽度断点。
///
/// 与旧版 Tailwind 的 `lg:` 断点一致：≥1024 逻辑像素走侧边栏，
/// 否则降级为底部 Tab Bar。
const double sidebarBreakpoint = 1024;

/// 侧边栏宽度。
const double sidebarWidth = 256;

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
// 外观与主题
// ═══════════════════════════════════════════════════════════════

/// 默认主色：薄荷绿。与旧版强调色一致，保证升级后观感不变。
///
/// 存的是 ARGB。用户选择的是**色种（seed）**，最终强调色由
/// `ui/theme/lexi_colors.dart` 按明暗模式重新推导，以保证文字对比度。
const int defaultThemePrimaryColor = 0xFF35C989;

/// 默认次色：靛蓝。
///
/// 与语义色（危险红 / 成功绿 / 警告橙 / 关联紫）刻意错开：次色是装饰与
/// 次级动作的用色，不能和「出错」或「正确」混淆。
const int defaultThemeSecondaryColor = 0xFF5E5CE6;

/// 启动时等待外观设置的最长时间（毫秒）。
///
/// 主题存在本地数据库里，读一次通常只要几毫秒；万一数据库打开很慢，
/// 也不该让用户对着空窗口等。超时后先用默认外观启动，读到设置后会自动
/// 切过去。
const int appearancePreloadBudgetMs = 250;

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

/// 手动添加页一次最多接受的行数。
///
/// 与旧版 `components/add/manual-tab.tsx` 的 `MAX_ROWS` 一致：每行要单独
/// 打一次词典，100 行已经是一次「批量导入」的量级，再多就该走 CSV。
const int manualBatchMaxRows = 100;

/// 手动添加页单行的字符上限。
const int manualBatchMaxCharsPerLine = 1200;

/// 手动添加页整段文本的字符上限。
const int manualBatchMaxTotalChars = 24000;

/// 手动添加页单行超限报错里截取的输入片段长度。
///
/// 与旧版 `components/add/manual-tab.tsx` 的 `overlong.slice(0, 24)` 一致：
/// 报错要让人认出是哪一行，又不该把一整段 1200 字符的内容贴进提示里。
const int manualBatchErrorSnippetLength = 24;

/// 手动添加页生成预览时的并发数。
///
/// 与旧版 `PREVIEW_CONCURRENCY` 一致：词典站点对并发敏感，串行又太慢。
const int manualBatchPreviewConcurrency = 5;

/// 答题计时在多久没有交互后暂停（毫秒）。
///
/// 与旧版 `lib/use-active-stopwatch.ts` 的 `ACTIVE_IDLE_TIMEOUT_MS` 一致
/// （45 秒）：统计的是「真正在答题的时间」，挂机、切窗口、锁屏都不该算进去。
/// 短于这个间隔的停顿视为思考的一部分。
const int activeIdleTimeoutMs = 45 * secondMs;

// ═══════════════════════════════════════════════════════════════
// 小游戏 / 配对 / 音标训练
//
// 数值来源逐条标注旧版出处。旧版把权重分散在 `games/completion.ts`、
// `matching/service.ts`、`games/service.ts` 三处（见 CLEAN_CODE_BASELINE），
// 这里收敛成唯一出处。
// ═══════════════════════════════════════════════════════════════

/// 开局所需的最少题数（旧版 `MINIMUM_GAME_ITEMS`）。
const int gameMinimumItemCount = 4;

/// 选择题的选项数量（旧版 `CHOICE_COUNT`）。
const int gameChoiceCount = 4;

/// 一道题至少要有几个选项才算可用。
///
/// 只有 1 个选项的题没有判别意义（选不选都是它），界面据此提示题库不足。
const int gameMinimumChoiceCount = 2;

/// 候选池一次取用的行数上限（旧版 `CANDIDATE_QUERY_LIMIT`）。
///
/// 旧版每次开局都跑一次全表排序再截断；这里是同一策略的显式上限，
/// 避免题库上万条时把整张表读进内存。
const int gameCandidateQueryLimit = 160;

/// 连击加成最多累计的级数，防止长连击把单题分值放大到失控。
const int gameComboCap = 5;

/// 快答阈值：低于此耗时的作答获得速度奖励。
const int gameFastAnswerMs = 3000;

/// 快答奖励分值。
const int gameFastAnswerBonus = 20;

/// 慢答阈值：达到此耗时的作答扣除速度分。
const int gameSlowAnswerMs = 12000;

/// 慢答扣分分值。
const int gameSlowAnswerPenalty = 10;

/// 评级 S 的得分占理论上限的百分比下限。
const int gameRankSPercent = 85;

/// 评级 A 的得分占理论上限的百分比下限。
const int gameRankAPercent = 70;

/// 评级 B 的得分占理论上限的百分比下限。
const int gameRankBPercent = 45;

/// 高分榜展示的条数（旧版 `LEADERBOARD_LIMIT`）。
const int leaderboardLimit = 10;

// ═══════════════════════════════════════════════════════════════
// 计分权重——旧版两套权重的唯一收敛点
//
// 旧版 `modules/games/completion.ts` 与 `modules/matching/service.ts`
// 各写了一套权重（`docs/CLEAN_CODE_BASELINE.md` 点名的重复）：
//   小游戏：firstTry*100 + recovered*55 + maxCombo*12 − mistake*20
//   配对：  firstTry*120 + recovered*70 + min(600, 剩余ms/100) + maxCombo*15 − mistake*25
//   音标：  firstTry*120 + recovered*60 + maxCombo*15 − mistake*20
// 收敛后只保留「基础分 / 连击步长 / 失误罚分 / 剩余时间换算」四类，
// 上表里 `recovered` 的低权重由「答错清零连击」自然实现。
// ═══════════════════════════════════════════════════════════════

/// 六个小游戏的基础分（旧版 `firstTryCorrect * 100`）。
const int gameBasePoints = 100;

/// 六个小游戏的连击步长（旧版 `maxCombo * 12`）。
const int gameComboStep = 12;

/// 六个小游戏的失误罚分（旧版 `mistakeCount * 20`）。
const int gameMistakePenalty = 20;

/// 配对游戏的基础分（旧版 `firstTryCorrect * 120`）。
const int matchBasePoints = 120;

/// 配对游戏的连击步长（旧版 `maxCombo * 15`）。
const int matchComboStep = 15;

/// 配对游戏的失误罚分（旧版 `mistakeCount * 25`）。
const int matchMistakePenalty = 25;

/// 配对游戏「剩余时间换分」的换算分母（旧版 `remainingMs / 100`）。
const int matchRemainingTimeDivisorMs = 100;

/// 配对游戏「剩余时间换分」的上限（旧版 `Math.min(600, …)`）。
const int matchRemainingTimeBonusCap = 600;

/// 音标训练的基础分（旧版 `firstTryCorrect * 120`）。
const int phoneticBasePoints = 120;

/// 音标训练的连击步长（旧版 `maxCombo * 15`）。
const int phoneticComboStep = 15;

/// 音标训练的失误罚分（旧版 `mistakeCount * 20`）。
const int phoneticMistakePenalty = 20;

// ═══════════════════════════════════════════════════════════════
// 各模式的题量与时限（旧版 `GAME_CONFIGS`）
// ═══════════════════════════════════════════════════════════════

/// 单词拼图的题量。
const int wordBuilderItemCount = 8;

/// 单词拼图的时限（秒）。
const int wordBuilderDurationSeconds = 90;

/// 听音辨词的题量。
const int listeningPickItemCount = 8;

/// 听音辨词的时限（秒）。
const int listeningPickDurationSeconds = 60;

/// 词义冲刺的题量。
const int meaningBlitzItemCount = 10;

/// 词义冲刺的时限（秒）。
const int meaningBlitzDurationSeconds = 45;

/// 词汇地鼠的题量。
const int whackAMoleItemCount = 10;

/// 词汇地鼠的时限（秒）。
const int whackAMoleDurationSeconds = 60;

/// 单词堆堆乐的题量。
const int wordStackItemCount = 8;

/// 单词堆堆乐的时限（秒）。
const int wordStackDurationSeconds = 75;

/// 词汇俄罗斯方块的题量。
const int wordTetrisItemCount = 10;

/// 词汇俄罗斯方块的时限（秒）。
const int wordTetrisDurationSeconds = 75;

/// 配对的默认对数。
const int matchingDefaultPairCount = 6;

/// 配对的最少对数（旧版 `MINIMUM_PAIR_COUNT`）。
const int matchingMinimumPairCount = 4;

/// 配对的最多对数（旧版 `MAXIMUM_PAIR_COUNT`）。
const int matchingMaximumPairCount = 8;

/// 配对的默认时限（秒）。
///
/// 与旧版默认预设「标准挑战」（6 组 / 60 秒）一致；`matchPresets` 里的
/// 三档预设会覆盖它。
const int matchingDefaultDurationSeconds = 60;

/// 配对的最短时限（秒，旧版 `MINIMUM_DURATION_SECONDS`）。
const int matchingMinimumDurationSeconds = 30;

/// 配对的最长时限（秒，旧版 `MAXIMUM_DURATION_SECONDS`）。
const int matchingMaximumDurationSeconds = 180;

/// 音标训练的题量（旧版 `GAME_ITEM_COUNT`）。
const int phoneticItemCount = 10;

/// 音标训练的时限（秒，旧版 `GAME_DURATION_SECONDS`）。
const int phoneticDurationSeconds = 75;

/// 音标训练所需的最少题数（旧版 `MINIMUM_ITEMS`）。
const int phoneticMinimumItemCount = 4;

/// 音标训练的选项数量（旧版 `OPTION_COUNT`）。
const int phoneticChoiceCount = 4;

/// 音标训练一次取用的候选池上限（旧版 `CANDIDATE_POOL_SIZE`）。
///
/// 取值 48 与音标目录规模一致：候选池要足够大，才能凑出
/// 「同类音标」的干扰项。
const int phoneticCandidatePoolSize = 48;

/// 音标训练的会话来源标识。
///
/// **与旧版的差异**：旧版复用 `GAME_PHONETICS`，会被
/// `ReviewService._isExcludedSource` 的 `GAME_` 前缀规则一起排除；
/// 本版改用独立标识，让「音标训练不写复习日志」这条规则在会话表里自解释。
const String phoneticTrainingSourceType = 'PHONETIC_TRAINING';

// ═══════════════════════════════════════════════════════════════
// 词汇地鼠（旧版 `whack-a-mole.tsx`）
// ═══════════════════════════════════════════════════════════════

/// 地鼠洞的数量（旧版 `HOLE_COUNT`）。
const int whackAMoleHoleCount = 6;

/// 地鼠停留时长（毫秒，旧版 `MOLE_STAY_MS`）。
const int whackAMoleStayMs = 2800;

/// 相邻地鼠冒头的间隔（毫秒，旧版 `STAGGER_MS`）。
const int whackAMoleStaggerMs = 130;

/// 第一只地鼠冒头前的延迟（毫秒，旧版硬编码 150）。
const int whackAMolePopDelayMs = 150;

// ═══════════════════════════════════════════════════════════════
// 单词堆堆乐（旧版 `word-stack.tsx`）
// ═══════════════════════════════════════════════════════════════

/// 点错的词块回落冷却（毫秒，旧版硬编码 620）。
const int wordStackBlockCooldownMs = 620;

/// 塔上可见的层数（旧版 `solvedTerms.slice(-4)`）。
const int wordStackTowerVisibleCount = 4;

// ═══════════════════════════════════════════════════════════════
// 词汇俄罗斯方块（旧版 `word-tetris.tsx`）
// ═══════════════════════════════════════════════════════════════

/// 堆叠上限（旧版 `TETRIS_DANGER_CAP`）：堆满即结束本局。
const int wordTetrisDangerCap = 5;

/// 方块下落的最短时长（毫秒，旧版 `FALL_MIN_MS`）。
const int wordTetrisFallMinMs = 4200;

/// 方块下落时长的随机跨度（毫秒，旧版 `FALL_SPREAD_MS`）。
const int wordTetrisFallSpreadMs = 1800;

/// 下落轨道数（旧版把 4 列写死在 `shuffle([0,1,2,3])` 里）。
const int wordTetrisColumnCount = 4;

// ═══════════════════════════════════════════════════════════════
// 音标目录与出题
// ═══════════════════════════════════════════════════════════════

/// 48 音标框架的音标总数——目录完整性由测试断言。
const int phonemeCatalogSize = 48;

/// 音标目录里元音（含双元音）的数量。
const int phonemeVowelCount = 20;

/// 音标目录里辅音的数量。
const int phonemeConsonantCount = 28;

// ═══════════════════════════════════════════════════════════════
// 选择题的作答节奏（旧版 `app/(main)/games/page.tsx`）
//
// 这两个值不在旧版 `GAME_CONFIGS` 里，而是硬编码在页面组件的
// `setTimeout` 里；集中到常量后，状态机可以按「毫秒」推进并单测。
// ═══════════════════════════════════════════════════════════════

/// 进入听音辨词 / 词义冲刺的每一题后，自动朗读该词条前的延迟（毫秒）。
///
/// 旧版 `games/page.tsx:114` 的 `window.setTimeout(..., 180)`：立刻朗读会与
/// 上一题的播放叠在一起，等一帧多一点再播才像「本题开始」。
const int gameAutoSpeakDelayMs = 180;

/// 选择题答错后红框反馈的停留时长（毫秒）。
///
/// 旧版 `games/page.tsx:217` 的 `setTimeout(() => setWrongChoice(null), 420)`：
/// 反馈期内忽略点击，避免用户连点把同一个错误选项刷成一串失误。
const int gameWrongChoiceFeedbackMs = 420;

// ═══════════════════════════════════════════════════════════════
// 文章导入（AI 选词的输入上限与输出结构）
//
// 数值来源逐条标注旧版出处：`modules/article-import/extract.ts`（词形与分段）、
// `service.ts`（候选与 AI 输入上限）、`schema.ts`（AI 输出结构，逐条对应 zod）。
// ═══════════════════════════════════════════════════════════════
// ── 词形提取（旧版 modules/article-import/extract.ts） ──

/// 词形的最短字符数。
///
/// 旧版 `extract.ts` 的 `stripped.length < 2` 与 `normalized.length < 2`。
const int articleTokenMinChars = 2;

/// 词形的最长字符数。
///
/// 旧版 `extract.ts` 的 `stripped.length > 30` 与 `normalized.length > 30`。
const int articleTokenMaxChars = 30;

/// 「单换行也算分段」所需的最少非空行数。
///
/// 旧版 `extract.ts` 的 `splitIntoParagraphs`：只有一整块、却含换行时，
/// 至少两行才按行拆段。
const int articleParagraphMinLines = 2;

// ── 预览与候选（旧版 service.ts / candidates.ts） ──

/// 送进 AI 提示词的「已掌握词」样本上限。
///
/// 旧版 `service.ts` 的 `existingRows.slice(0, 30)` 与
/// `prompt.ts` 的 `knownSample.slice(0, 30)`。
const int articleKnownSampleLimit = 30;

/// 本地切句的候选上限（用于给候选词找出处句、以及拼进 AI 的文章片段）。
///
/// 旧版 `service.ts` 的 `extractSentences(cleaned)...slice(0, 40)`。
const int articleSentenceCandidateLimit = 40;

/// 拼进 AI 文章片段的句子条数上限。
///
/// 旧版 `service.ts` 的 `sentencesRaw.slice(0, 15)`。
const int articleAiSnippetSentenceLimit = 15;

/// 合并预览时，「全文词数」缺失时的估算倍数。
///
/// 旧版 `candidates.ts` 的 `wordCount: totalWordCount || uniqueCount * 2`。
const int articleWordCountEstimateFactor = 2;

/// 预览令牌的字符数。
///
/// 本版新增：旧版用 `crypto.randomUUID()` 生成服务端预览令牌，
/// Dart 侧用等长随机十六进制串代替（见 `ArticleImportService`）。
const int articlePreviewTokenLength = 32;

/// 报错文案里回显的令牌前缀长度。
///
/// 本版新增：旧版 `mergeArticlePreviews` 的报错用 `token.slice(0, 8)`，
/// 那是 UUID 前 8 位；本版令牌长度不同，取前一半（16 位）同样够定位。
const int articleShortTokenChars = 16;

// ── AI 输出结构上限（旧版 modules/article-import/schema.ts） ──

/// AI 返回的单词条数上限（旧版 `max(100)`）。
const int articleAiWordsMaxItems = 100;

/// 宽容解析接受的短语条数上限（旧版 `max(20)`；真正的上限由
/// `articlePhraseLimit` 在合并阶段施加）。
const int articleAiPhrasesMaxItems = 20;

/// 宽容解析接受的句子条数上限（旧版 `max(20)`；真正的上限由
/// `articleSentenceLimit` 在合并阶段施加）。
const int articleAiSentencesMaxItems = 20;

/// 短语卡片的重点词汇条数上限（旧版 `max(8)`）。
const int articleAiPhraseKeyVocabMaxItems = 8;

/// 句子卡片的重点词汇条数上限（旧版 `max(10)`）。
const int articleAiSentenceKeyVocabMaxItems = 10;

/// 语法要点条数上限（旧版 `max(4)`）。
const int articleAiGrammarNotesMaxItems = 4;

/// 词条文本的字符数上限（旧版 `term: max(60)`）。
const int articleAiTermMaxChars = 60;

/// 推荐理由的字符数上限（旧版 `reason: max(40)`）。
const int articleAiReasonMaxChars = 40;

/// 重点词汇词形的字符数上限（旧版 `max(40)`）。
const int articleAiKeyVocabTermMaxChars = 40;

/// 重点词汇词性的字符数上限（旧版 `max(20)`）。
const int articleAiKeyVocabPosMaxChars = 20;

/// 重点词汇释义的字符数上限（旧版 `max(80)`）。
const int articleAiKeyVocabMeaningMaxChars = 80;

/// 语法句型的字符数上限（旧版 `max(120)`）。
const int articleAiGrammarPatternMaxChars = 120;

/// 单条语法说明的字符数上限（旧版 `max(200)`）。
const int articleAiGrammarNoteMaxChars = 200;

/// 短语直译 / 意译的字符数上限（旧版 `max(200)`）。
const int articleAiPhraseTranslationMaxChars = 200;

/// 短语辨析的字符数上限（旧版 `max(120)`）。
const int articleAiPhraseNuanceMaxChars = 120;

/// 句子原文的字符数上限（旧版 `sentence: max(600)`）。
const int articleAiSentenceTextMaxChars = 600;

/// 句子直译 / 意译的字符数上限（旧版 `max(400)`）。
const int articleAiSentenceTranslationMaxChars = 400;

/// 句子注释的字符数上限（旧版 `max(200)`）。
const int articleAiSentenceNuanceMaxChars = 200;

/// 难度取值上限（旧版 `difficulty: min(1).max(5)`；下限 1 无需具名）。
const int articleAiDifficultyMax = 5;

/// 难度无法解析时的兜底值（旧版 `lenientDifficulty` 的 `return 3`）。
const int articleAiDifficultyFallback = 3;

/// 文章 AI 分词「原文变形词（surface）」字符上限。
const int articleAiSurfaceMaxChars = 60;

/// 文章 AI 分词单个考试标签字符上限。
const int articleAiExamTagMaxChars = 16;

/// 文章 AI 分词单个单词附带的考试标签条数上限。
const int articleAiExamTagsMaxItems = 4;

/// 仅分词模式（不含短语与难句卡片）的输出 token 下限。
const int articleAiWordOnlyMaxOutputTokens = 2400;

/// 网页文章抓取提取正文的最小有效字符数（低于此值回退到整页提取）。
const int articleHtmlMainMinChars = 80;

/// 网页 / 本地文章文件读取的最大字节数（2 MB，防止误选超大文件卡死内存）。
const int maxArticleFileBytes = 2 * 1024 * 1024;

/// 自定义列映射向导预览展示的样本行数。
const int csvColumnMappingSampleRows = 5;

/// HTML 实体十六进制解析基数。
const int hexRadix = 16;

/// HTML 实体十进制解析基数。
const int decimalRadix = 10;

/// 合法 Unicode 码点上限。
const int maxUnicodeCodePoint = 0x10FFFF;

// ── 本模块的字符串常量（无数字，无需豁免） ──

/// 默认源语言。
///
/// 与旧版 `/api/article-import/preview` 的 `sourceLanguage ?? "en"` 一致。
const String articleDefaultSourceLanguage = 'en';

/// 默认目标语言。
///
/// 与旧版一致（**不是** CSV 导入页的 `zh`）：`zh-CN` 才是真实词库里的取值。
const String articleDefaultTargetLanguage = 'zh-CN';

/// 段落拼接分隔符（旧版用 `"\n\n"` 拼回被合并的段落）。
const String articleParagraphSeparator = '\n\n';

/// 分段 ID 前缀（旧版 `seg-1`、`seg-2`…）。
const String articleSegmentIdPrefix = 'seg-';

/// AI 未给出理由时的兜底理由（旧版 `schema.ts` 的 `?? "值得学习"`）。
const String articleDefaultReason = '值得学习';

// ═══════════════════════════════════════════════════════════════
// 词典管线 / LLM 降级 / 每日建议
//
// 数值来源逐条标注旧版出处：`dictionary/pipeline.ts`（提前终止质量分）、
// `modules/llm/client.ts`（超时与 token 边界）、`modules/suggestions/*`（权重与阈值）。
// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// 词典合并管线：PRIORITY_FALLBACK 的提前终止质量分
// （对应旧版 `dictionary/pipeline.ts` 的 fallbackQualityScore）
// ═══════════════════════════════════════════════════════════════

/// 质量分中「目标语言释义」的权重。
///
/// 释义是判题的唯一依据：没有释义的选择题没有选项，权重必须最高。
const double fallbackQualityTargetDefinitionWeight = 0.5;

/// 质量分中「例句数量」的权重。
const double fallbackQualityExamplesWeight = 0.3;

/// 质量分中「音标」的权重。
const double fallbackQualityPhoneticsWeight = 0.2;

/// 只有部分满足某分项时乘以的折扣系数（对应旧版 1 / 0.5 / 0）。
const double fallbackQualityPartialFactor = 0.5;

/// 完全满足某分项时乘以的系数。
const double fallbackQualityFullFactor = 1;

/// 例句「充足」所需的条数。
const int fallbackQualityExamplesFullCount = 2;

/// 例句「勉强够用」所需的条数。
const int fallbackQualityExamplesPartialCount = 1;

/// 句子类词条缺少译文时的质量分上限。
///
/// 句子没有中文译文就无法判分，即使字段齐全也不能算高质量，
/// 否则 PRIORITY_FALLBACK 会在第一个 provider 就停下。
const double fallbackQualitySentenceTranslationCap = 0.6;

// ═══════════════════════════════════════════════════════════════
// 字段完备性判定（对应旧版 `dictionary/selection.ts`）
// ═══════════════════════════════════════════════════════════════

/// `sentenceAnalysis` 视为完备所需的同结构例句数。
///
/// 旧版要求 ≥3：少于 3 条无法让学习者归纳出句型。
const int sentenceAnalysisMinSimilarExamples = 3;

// ═══════════════════════════════════════════════════════════════
// 初始化任务查询（对应旧版 `initialization/queries.ts`）
// ═══════════════════════════════════════════════════════════════

/// 初始化任务列表的默认分页大小。
const int initializationJobPageSize = 50;

// ═══════════════════════════════════════════════════════════════
// 每日建议：候选排序权重
// （对应旧版 `suggestions/constants.ts` 的 SUGGESTION_SCORE_WEIGHTS）
// ═══════════════════════════════════════════════════════════════

/// 每日建议候选的排序权重。
///
/// 旧版把这些值写成 `score()` 里的 13 个裸权重，被
/// `docs/CLEAN_CODE_BASELINE.md` 点名；这里逐个具名，
/// 并保留旧版数值以便与线上表现对齐。
class SuggestionScoreWeights {
  /// 以各权重构造。
  const new({
    required this.incorrect,
    required this.again,
    required this.hard,
    required this.wrongActive,
    required this.wrongCount,
    required this.hardCount,
    required this.dueToday,
    required this.difficulty,
    required this.lapses,
    required this.fallback,
    required this.durationBaselineMs,
    required this.durationStepMs,
    required this.durationMaxBonus,
    required this.overdueMaxBonus,
    required this.overduePerDay,
  });

  /// 昨日答错一次的分值。
  final int incorrect;

  /// 昨日选择「忘记」一次的分值。
  final int again;

  /// 昨日选择「模糊」一次的分值。
  final int hard;

  /// 仍处于活跃错词状态的分值。
  final int wrongActive;

  /// 累计答错次数的每单位分值。
  final int wrongCount;

  /// 累计模糊次数的每单位分值。
  final int hardCount;

  /// 今天到期的分值。
  final int dueToday;

  /// FSRS 难度的每单位分值。
  final int difficulty;

  /// FSRS 遗忘次数的每单位分值。
  final int lapses;

  /// 「无风险候选时兜底补位」的分值。
  final int fallback;

  /// 平均作答时长基线（毫秒）：低于此值不计入分值。
  final int durationBaselineMs;

  /// 超过基线后每多少毫秒加 1 分。
  final int durationStepMs;

  /// 作答时长分项的分值上限。
  final int durationMaxBonus;

  /// 逾期分项的分值上限。
  final int overdueMaxBonus;

  /// 逾期每一天的分值。
  final int overduePerDay;
}

/// 每日建议候选排序权重的唯一实例。
const SuggestionScoreWeights suggestionScoreWeights = SuggestionScoreWeights(
  incorrect: 120,
  again: 75,
  hard: 38,
  wrongActive: 55,
  wrongCount: 7,
  hardCount: 4,
  dueToday: 22,
  difficulty: 2,
  lapses: 5,
  fallback: 1,
  durationBaselineMs: 7 * secondMs,
  durationStepMs: 300,
  durationMaxBonus: 45,
  overdueMaxBonus: 35,
  overduePerDay: 4,
);

// ═══════════════════════════════════════════════════════════════
// 每日建议：质量分（对应旧版 `suggestions/metrics.ts`）
// ═══════════════════════════════════════════════════════════════

/// 每日建议质量分的合成权重。
class SuggestionQualityWeights {
  /// 以各权重构造。
  const new({
    required this.againPenalty,
    required this.hardPenalty,
    required this.stabilityScale,
    required this.speedBaselineMs,
    required this.speedDivisor,
    required this.speedDefault,
    required this.speedFloor,
    required this.completionDefault,
    required this.accuracyWeight,
    required this.stabilityWeight,
    required this.speedWeight,
    required this.completionWeight,
  });

  /// 每题「忘记」的挑战度罚分。
  final double againPenalty;

  /// 每题「模糊」的挑战度罚分。
  final double hardPenalty;

  /// 挑战度换算为稳定性得分的放大系数。
  final double stabilityScale;

  /// 速度得分基线（毫秒）：低于此值速度满分。
  final int speedBaselineMs;

  /// 超过基线后每多少毫秒扣 1 分。
  final double speedDivisor;

  /// 没有时长数据时的速度得分。
  final double speedDefault;

  /// 速度得分下限。
  final double speedFloor;

  /// 没有完成率数据时的默认完成率。
  final double completionDefault;

  /// 正确率权重。
  final double accuracyWeight;

  /// 稳定性权重。
  final double stabilityWeight;

  /// 速度权重。
  final double speedWeight;

  /// 完成率权重。
  final double completionWeight;
}

/// 每日建议质量分权重的唯一实例。
const SuggestionQualityWeights suggestionQualityWeights =
    SuggestionQualityWeights(
      againPenalty: 1.5,
      hardPenalty: 0.7,
      stabilityScale: 55,
      speedBaselineMs: 5 * secondMs,
      speedDivisor: 180,
      speedDefault: 70,
      speedFloor: 35,
      completionDefault: 70,
      accuracyWeight: 0.58,
      stabilityWeight: 0.2,
      speedWeight: 0.08,
      completionWeight: 0.14,
    );

// ═══════════════════════════════════════════════════════════════
// 每日建议：规则式文案阈值（对应旧版 `suggestions/content.ts`）
// ═══════════════════════════════════════════════════════════════

/// 规则式建议文案使用的判定阈值。
class SuggestionTextThresholds {
  /// 以各阈值构造。
  const new({
    required this.lowAccuracyPercent,
    required this.strengthAccuracyPercent,
    required this.strengthCompletionPercent,
    required this.strengthStudyMinutes,
    required this.headlineWeakAccuracyPercent,
    required this.headlineStrongAccuracyPercent,
    required this.slowAverageDurationMs,
    required this.weakQuestionAccuracyPercent,
    required this.overloadMinSkipped,
    required this.overloadSkipRatio,
    required this.strengthReviewCount,
    required this.riskLimit,
  });

  /// 低于此正确率视为「需要修复错误」。
  final int lowAccuracyPercent;

  /// 达到此正确率可作为亮点。
  final int strengthAccuracyPercent;

  /// 达到此完成率可作为亮点。
  final int strengthCompletionPercent;

  /// 达到此学习分钟数可作为亮点。
  final int strengthStudyMinutes;

  /// 标题分档：低于此正确率时标题为「先修复错误」。
  final int headlineWeakAccuracyPercent;

  /// 标题分档：达到此正确率且完成率高时为「保持状态」。
  final int headlineStrongAccuracyPercent;

  /// 平均作答时长超过此值视为「偏慢」。
  final int slowAverageDurationMs;

  /// 题型正确率低于此值才提示该题型薄弱。
  final int weakQuestionAccuracyPercent;

  /// 跳过题数的绝对下限。
  final int overloadMinSkipped;

  /// 跳过题数占作答数的比例下限。
  final double overloadSkipRatio;

  /// 作答量达到此值且零跳过才算「完整完成」。
  final int strengthReviewCount;

  /// 风险条目最多展示几条。
  final int riskLimit;
}

/// 规则式建议文案阈值的唯一实例。
const SuggestionTextThresholds suggestionTextThresholds =
    SuggestionTextThresholds(
      lowAccuracyPercent: 75,
      strengthAccuracyPercent: 80,
      strengthCompletionPercent: 90,
      strengthStudyMinutes: 15,
      headlineWeakAccuracyPercent: 60,
      headlineStrongAccuracyPercent: 85,
      slowAverageDurationMs: 15 * secondMs,
      weakQuestionAccuracyPercent: 75,
      overloadMinSkipped: 3,
      overloadSkipRatio: 0.25,
      strengthReviewCount: 10,
      riskLimit: 4,
    );

// ═══════════════════════════════════════════════════════════════
// 每日建议：候选池规模与时间窗
// ═══════════════════════════════════════════════════════════════

/// 打分后保留的候选数量上限。
const int suggestionCandidateLimit = 30;

/// 没有任何风险候选时，兜底补位的词条数量。
const int suggestionFallbackCandidateLimit = 12;

/// 活跃错词的扫描上限。
const int suggestionWrongWordScanLimit = 200;

/// 到期卡片的扫描上限。
const int suggestionDueCardScanLimit = 200;

/// 最终推荐条目数量上限（对应旧版 `RECOMMENDATION_LIMIT`）。
const int suggestionRecommendationLimit = 8;

/// 统计指标的回看窗口。
///
/// 按自然日筛选，因此至少要覆盖「昨天」；取 3 天以容忍时区与夏令时边界。
const int suggestionMetricsLookbackMs = 3 * dayMs;

// ═══════════════════════════════════════════════════════════════
// LLM 配置的取值边界（对应旧版 `settings/service.ts` 的 zod schema）
// ═══════════════════════════════════════════════════════════════

/// 温度下限。
const double minLlmTemperature = 0;

/// 温度上限。
const double maxLlmTemperature = 1;

/// 开启思考时强制使用的温度。
///
/// Anthropic 的 extended thinking 只接受 `temperature = 1`。
const double llmThinkingTemperature = 1;

/// 最大输出 token 下限。
const int minLlmMaxOutputTokens = 500;

/// 最大输出 token 上限。
const int maxLlmMaxOutputTokens = 200000;

/// `aiRetryCount` 的默认值。
const int defaultAiRetryCount = 1;

/// `aiRetryCount` 的上限。
const int maxAiRetryCount = 5;

/// Anthropic 开启思考时，输出上限额外预留的 token。
///
/// 思考 token 与正文 token 共用 `max_tokens` 预算，不留余量会被截断。
const int anthropicThinkingOutputHeadroomTokens = 1024;

/// Anthropic API 版本头。
const String anthropicVersionHeader = '2023-06-01';

/// 判定「请求本身有误」的状态码。
const int httpBadRequestStatus = 400;

/// 错误摘要截断长度（写进错误详情，避免整页 HTML 进日志）。
const int llmErrorSnippetChars = 120;

/// 推理模型标识前缀：这些模型用 `reasoning_effort` 而不是 `temperature`。
const List<String> llmReasoningModelPrefixes = <String>['o1', 'o3', 'gpt-5'];

/// 默认推理强度。
const String llmDefaultReasoningEffort = 'low';

/// Anthropic 思考参数不合法时的状态码提示关键词。
const List<String> llmThinkingRejectionKeywords = <String>[
  'thinking',
  'reasoning',
  'reasoning_effort',
  'budget_tokens',
];

// ═══════════════════════════════════════════════════════════════
// AI 词条内容的质量门（对应旧版 `ai-lexical-content.ts`）
// ═══════════════════════════════════════════════════════════════

/// 助记词被视为「中文」所需的最少汉字数。
///
/// 少于 8 个汉字通常是模型把英文解释直接塞进了助记字段。
const int aiMnemonicMinChineseChars = 8;

/// AI 建议质量分的分项权重（对应 `aiSuggestionQualityScore`）。
const int aiSuggestionHeadlineWeight = 30;

/// AI 建议质量分：总结权重。
const int aiSuggestionSummaryWeight = 20;

/// AI 建议质量分：行动建议充分时的权重。
const int aiSuggestionActionsWeight = 20;

/// AI 建议质量分：只有一条行动建议时的权重。
const int aiSuggestionSingleActionWeight = 10;

/// AI 建议质量分：有风险提示时的权重。
const int aiSuggestionRisksWeight = 10;

/// AI 建议质量分：推荐条目落在候选池内时的权重。
const int aiSuggestionRecommendedWeight = 20;

/// AI 建议质量分：行动建议「充分」所需条数。
const int aiSuggestionMinActions = 2;

/// AI 建议提示词里声明的亮点条数上限。
const int suggestionAiMaxStrengths = 3;

/// AI 建议提示词里声明的风险条数上限。
const int suggestionAiMaxRisks = 4;

/// AI 建议提示词里声明的行动建议条数下限。
const int suggestionAiMinActions = 2;

/// AI 建议提示词里声明的行动建议条数上限。
const int suggestionAiMaxActions = 3;

/// 推荐理由最多拼接的分句数。
const int suggestionReasonPartLimit = 2;

/// 双精度零值。
///
/// 架构守卫只豁免整数 `0`，浮点字面量 `0.0` 会被判为裸数字，
/// 因此需要 `double` 上下文的零值必须具名。
const double zeroDouble = 0;

/// 百分数换算基数。
///
/// `lib/services` 禁止裸数字字面量，而正确率 / 完成率到处要 `* 100`。
const int percentScale = 100;

/// 结构化输出中 JSON Schema 的名字。
const String llmJsonSchemaName = 'lexiloop_lexical_content';

// ═══════════════════════════════════════════════════════════════
// 音频播放层（真人发音下载与预取）
//
// 数值与协议常量来源：旧版 `src/modules/tts/service.ts` 的 `fetchYoudaoAudio`、
// `src/lib/tts-client.ts` 的 `preloadTtsBatch`。
// ═══════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════
// 有道真人发音（对应旧版 src/modules/tts/service.ts 的 fetchYoudaoAudio）
// ═══════════════════════════════════════════════════════════════

/// 有道发音端点。
///
/// 来源：旧版 `src/modules/tts/service.ts` 的 `fetchYoudaoAudio` 模板串。
const String youdaoAudioEndpoint = 'https://dict.youdao.com/dictvoice';

/// 词条在 URL 中的查询参数名。
const String youdaoAudioQueryKey = 'audio';

/// 口音在 URL 中的查询参数名。
const String youdaoAudioTypeQueryKey = 'type';

/// 有道词典的来源标识，与 `pronunciations[].source` 的取值逐字对应。
///
/// 取自 `lib/data/dictionary/providers/youdao_fields.dart` 写库时的
/// `'source': 'youdao'`。之所以在这里重述而不直接 import provider 常量：
/// 音频层不该为了一个字符串标识依赖整个词典 provider 实现。
const String youdaoAudioSource = 'youdao';

// ═══════════════════════════════════════════════════════════════
// 下载与预取
// ═══════════════════════════════════════════════════════════════

/// 批量预取真人录音时的并发下载数。
///
/// 对应旧版 `src/lib/tts-client.ts` 的 `preloadTtsBatch(items, maxConcurrent = 2)`。
/// 取 2 而不是更高：预取发生在学习界面刚挂载、网络正被主流程占用的时刻，
/// 并发拉高只会让首屏更慢、也更容易触发词典站点限流。
const int audioPreloadConcurrency = 2;

/// 下载音频时使用的 User-Agent。
///
/// 与旧版 `fetchYoudaoAudio` 的请求头逐字一致。部分词典站点会拒绝没有
/// UA 的请求，缺了这一行会表现为「音频地址存在但永远放不出来」。
const String audioUserAgent = 'Mozilla/5.0 LexiLoop';

/// 下载音频时声明可接受的类型。
const String audioAcceptHeader = 'audio/mpeg,*/*';

/// 缓存中音频字节的内容类型，供播放器构造数据源时使用。
const String audioContentType = 'audio/mpeg';

/// HTTP 2xx 成功状态码下界（含）。
const int httpStatusOkMin = 200;

/// HTTP 2xx 成功状态码上界（不含）。
const int httpStatusOkMax = 300;

/// 词库搜索输入防抖时长（毫秒）。
const int wordsSearchDebounceMs = 300;

// ═══════════════════════════════════════════════════════════════
// 词书包（云端下载、多通道加速与按需有道补全）
// ═══════════════════════════════════════════════════════════════

/// 默认词书包托管仓库（`owner/repo`）。
const String wordPackDefaultRepo = 'lengsukq/LexiLoop-packs';

/// 默认词书包仓库标签/分支。
const String wordPackDefaultRef = 'v1.0.0';

/// 远端词书目录清单的相对路径。
const String wordPackCatalogRelativePath = 'catalog.json';

/// 应用内置的离线词书目录资源路径。
const String wordPackBundledCatalogAsset = 'assets/wordbooks/catalog.json';

/// 词书包格式标识。
const String wordPackFormatId = 'lexiloop-wordbook-pack';

/// 词书包格式版本号。
const int wordPackFormatVersion = 1;

/// 词书包下载通道设置的持久化键（存于 `settings` 表）。
const String wordPackDownloadSettingsKey = 'wordPackDownloadConfig';

/// 词书包通道连通性探测超时（毫秒）。
const int wordPackChannelProbeTimeoutMs = 5 * secondMs;

/// 词书包文件下载超时（毫秒）。
const int wordPackDownloadTimeoutMs = 2 * minuteMs;

/// 词书包压缩文件安全大小上限（32 MiB）。
const int wordPackMaxCompressedBytes = 32 * 1024 * 1024;

/// 词书包解压后 JSON 安全大小上限（128 MiB）。
const int wordPackMaxDecompressedBytes = 128 * 1024 * 1024;

/// 词书包入库时每批事务写入的词条数。
const int wordPackImportBatchSize = 500;

/// 词书包字节超过该阈值时转入后台 Isolate 解压与解析（64 KiB）。
const int wordPackIsolateThresholdBytes = 64 * 1024;

/// 按需懒加载有道补全的默认前瞻词数（优先补全即将学习的词条）。
const int wordPackLazyEnrichBatchSize = 30;

/// 按需懒加载有道补全的任务优先级（低于手动点击刷新，高于普通后台任务）。
const int wordPackLazyEnrichPriority = 80;

/// 词书包全量后台有道补全的任务优先级。
const int wordPackFullEnrichPriority = 40;

/// 词书专项学习会话的 `source_type` 前缀。
const String wordPackSessionSourcePrefix = 'PACK:';

/// 词书包标签前缀分隔时每张词条卡片最多展示的词书徽章数。
const int wordCardMaxPackBadges = 2;

/// 字节换算 KiB 的基数。
const int bytesPerKiB = 1024;

/// 字节换算 MiB 的基数。
const int bytesPerMiB = 1024 * 1024;

/// 词书包测速延迟的展示上限毫秒数（超时哨兵）。
const int wordPackLatencyTimeoutMs = 9999;

/// 词书包来源数据标识：ECDICT MIT 基础预填充。
const String ecdictDictionarySource = 'ecdict';
