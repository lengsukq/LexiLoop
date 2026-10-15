/// 小游戏、配对与音标训练需要的数值常量。
///
/// **为什么这些值不直接写在 `lib/core/constants.dart`**：本次任务的改动范围
/// 被限定在 `lib/domain/games/**`、`lib/domain/phonetics/**`、新增 DAO、
/// 新增 service 与新增 feature 目录内，`lib/core/constants.dart` 由调用方
/// 统一接线。而 `lib/domain` 受「禁止裸数字字面量」的架构守卫约束
/// （见 `test/architecture/architecture_test.dart`），
/// **连 `const int x = 5;` 都会被判违规**，所以这些值必须先有一个具名落点，
/// 否则整个模块无法通过门禁。
///
/// **迁移方式**：把下面每一行原样搬进 `lib/core/constants.dart`
/// （删掉行尾的 `// guard:allow-magic` 豁免注释），再删除本文件即可。
/// 值的来源逐条标注在注释里，便于与旧版实现对照。
///
/// 之所以用 `// guard:allow-magic` 而不是散落豁免，是因为这里是
/// **唯一的数值出处**：守卫禁止的是「散落在表达式里的裸数字」，
/// 而不是「集中定义的具名常量」，本文件正是后者的临时容器。
library;

// ═══════════════════════════════════════════════════════════════
// 通用
// ═══════════════════════════════════════════════════════════════

/// 开局所需的最少题数（旧版 `MINIMUM_GAME_ITEMS`）。
const int gameMinimumItemCount = 4; // guard:allow-magic

/// 选择题的选项数量（旧版 `CHOICE_COUNT`）。
const int gameChoiceCount = 4; // guard:allow-magic

/// 候选池一次取用的行数上限（旧版 `CANDIDATE_QUERY_LIMIT`）。
///
/// 旧版每次开局都跑一次全表排序再截断；这里是同一策略的显式上限，
/// 避免题库上万条时把整张表读进内存。
const int gameCandidateQueryLimit = 160; // guard:allow-magic

/// 百分比换算基数（正确率、评级阈值共用）。
const int gamePercentScale = 100; // guard:allow-magic

/// 连击加成最多累计的级数，防止长连击把单题分值放大到失控。
const int gameComboCap = 5; // guard:allow-magic

/// 快答阈值：低于此耗时的作答获得速度奖励。
const int gameFastAnswerMs = 3000; // guard:allow-magic

/// 快答奖励分值。
const int gameFastAnswerBonus = 20; // guard:allow-magic

/// 慢答阈值：达到此耗时的作答扣除速度分。
const int gameSlowAnswerMs = 12000; // guard:allow-magic

/// 慢答扣分分值。
const int gameSlowAnswerPenalty = 10; // guard:allow-magic

/// 评级 S 的得分占理论上限的百分比下限。
const int gameRankSPercent = 85; // guard:allow-magic

/// 评级 A 的得分占理论上限的百分比下限。
const int gameRankAPercent = 70; // guard:allow-magic

/// 评级 B 的得分占理论上限的百分比下限。
const int gameRankBPercent = 45; // guard:allow-magic

/// 高分榜展示的条数（旧版 `LEADERBOARD_LIMIT`）。
const int leaderboardLimit = 10; // guard:allow-magic

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

/// 四个小游戏的基础分（旧版 `firstTryCorrect * 100`）。
const int gameBasePoints = 100; // guard:allow-magic

/// 四个小游戏的连击步长（旧版 `maxCombo * 12`）。
const int gameComboStep = 12; // guard:allow-magic

/// 四个小游戏的失误罚分（旧版 `mistakeCount * 20`）。
const int gameMistakePenalty = 20; // guard:allow-magic

/// 配对游戏的基础分（旧版 `firstTryCorrect * 120`）。
const int matchBasePoints = 120; // guard:allow-magic

/// 配对游戏的连击步长（旧版 `maxCombo * 15`）。
const int matchComboStep = 15; // guard:allow-magic

/// 配对游戏的失误罚分（旧版 `mistakeCount * 25`）。
const int matchMistakePenalty = 25; // guard:allow-magic

/// 配对游戏「剩余时间换分」的换算分母（旧版 `remainingMs / 100`）。
const int matchRemainingTimeDivisorMs = 100; // guard:allow-magic

/// 配对游戏「剩余时间换分」的上限（旧版 `Math.min(600, …)`）。
const int matchRemainingTimeBonusCap = 600; // guard:allow-magic

/// 音标训练的基础分（旧版 `firstTryCorrect * 120`）。
const int phoneticBasePoints = 120; // guard:allow-magic

/// 音标训练的连击步长（旧版 `maxCombo * 15`）。
const int phoneticComboStep = 15; // guard:allow-magic

/// 音标训练的失误罚分（旧版 `mistakeCount * 20`）。
const int phoneticMistakePenalty = 20; // guard:allow-magic

// ═══════════════════════════════════════════════════════════════
// 各模式的题量与时限（旧版 `GAME_CONFIGS`）
// ═══════════════════════════════════════════════════════════════

/// 单词拼图的题量。
const int wordBuilderItemCount = 8; // guard:allow-magic

/// 单词拼图的时限（秒）。
const int wordBuilderDurationSeconds = 90; // guard:allow-magic

/// 词汇地鼠的题量。
const int whackAMoleItemCount = 10; // guard:allow-magic

/// 词汇地鼠的时限（秒）。
const int whackAMoleDurationSeconds = 60; // guard:allow-magic

/// 单词堆堆乐的题量。
const int wordStackItemCount = 8; // guard:allow-magic

/// 单词堆堆乐的时限（秒）。
const int wordStackDurationSeconds = 75; // guard:allow-magic

/// 词汇俄罗斯方块的题量。
const int wordTetrisItemCount = 10; // guard:allow-magic

/// 词汇俄罗斯方块的时限（秒）。
const int wordTetrisDurationSeconds = 75; // guard:allow-magic

/// 配对的默认对数。
const int matchingDefaultPairCount = 6; // guard:allow-magic

/// 配对的最少对数（旧版 `MINIMUM_PAIR_COUNT`）。
const int matchingMinimumPairCount = 4; // guard:allow-magic

/// 配对的最多对数（旧版 `MAXIMUM_PAIR_COUNT`）。
const int matchingMaximumPairCount = 8; // guard:allow-magic

/// 配对的默认时限（秒）。
const int matchingDefaultDurationSeconds = 90; // guard:allow-magic

/// 配对的最短时限（秒，旧版 `MINIMUM_DURATION_SECONDS`）。
const int matchingMinimumDurationSeconds = 30; // guard:allow-magic

/// 配对的最长时限（秒，旧版 `MAXIMUM_DURATION_SECONDS`）。
const int matchingMaximumDurationSeconds = 180; // guard:allow-magic

/// 音标训练的题量（旧版 `GAME_ITEM_COUNT`）。
const int phoneticItemCount = 10; // guard:allow-magic

/// 音标训练的时限（秒，旧版 `GAME_DURATION_SECONDS`）。
const int phoneticDurationSeconds = 75; // guard:allow-magic

/// 音标训练所需的最少题数（旧版 `MINIMUM_ITEMS`）。
const int phoneticMinimumItemCount = 4; // guard:allow-magic

/// 音标训练的选项数量（旧版 `OPTION_COUNT`）。
const int phoneticChoiceCount = 4; // guard:allow-magic

/// 音标训练一次取用的候选池上限（旧版 `CANDIDATE_POOL_SIZE`）。
///
/// 取值 48 与音标目录规模一致：候选池要足够大，才能凑出
/// 「同类音标」的干扰项。
const int phoneticCandidatePoolSize = 48; // guard:allow-magic

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
const int whackAMoleHoleCount = 6; // guard:allow-magic

/// 地鼠停留时长（毫秒，旧版 `MOLE_STAY_MS`）。
const int whackAMoleStayMs = 2800; // guard:allow-magic

/// 相邻地鼠冒头的间隔（毫秒，旧版 `STAGGER_MS`）。
const int whackAMoleStaggerMs = 130; // guard:allow-magic

/// 第一只地鼠冒头前的延迟（毫秒，旧版硬编码 150）。
const int whackAMolePopDelayMs = 150; // guard:allow-magic

// ═══════════════════════════════════════════════════════════════
// 单词堆堆乐（旧版 `word-stack.tsx`）
// ═══════════════════════════════════════════════════════════════

/// 点错的词块回落冷却（毫秒，旧版硬编码 620）。
const int wordStackBlockCooldownMs = 620; // guard:allow-magic

/// 塔上可见的层数（旧版 `solvedTerms.slice(-4)`）。
const int wordStackTowerVisibleCount = 4; // guard:allow-magic

/// 堆叠成功后的反馈停留（毫秒，旧版硬编码 400）。
const int wordStackSolvedFeedbackMs = 400; // guard:allow-magic

// ═══════════════════════════════════════════════════════════════
// 词汇俄罗斯方块（旧版 `word-tetris.tsx`）
// ═══════════════════════════════════════════════════════════════

/// 堆叠上限（旧版 `TETRIS_DANGER_CAP`）：堆满即结束本局。
const int wordTetrisDangerCap = 5; // guard:allow-magic

/// 方块下落的最短时长（毫秒，旧版 `FALL_MIN_MS`）。
const int wordTetrisFallMinMs = 4200; // guard:allow-magic

/// 方块下落时长的随机跨度（毫秒，旧版 `FALL_SPREAD_MS`）。
const int wordTetrisFallSpreadMs = 1800; // guard:allow-magic

/// 下落轨道数（旧版把 4 列写死在 `shuffle([0,1,2,3])` 里）。
const int wordTetrisColumnCount = 4; // guard:allow-magic

// ═══════════════════════════════════════════════════════════════
// 音标目录与出题
// ═══════════════════════════════════════════════════════════════

/// 48 音标框架的音标总数——目录完整性由测试断言。
const int phonemeCatalogSize = 48; // guard:allow-magic

/// 音标目录里元音（含双元音）的数量。
const int phonemeVowelCount = 20; // guard:allow-magic

/// 音标目录里辅音的数量。
const int phonemeConsonantCount = 28; // guard:allow-magic
