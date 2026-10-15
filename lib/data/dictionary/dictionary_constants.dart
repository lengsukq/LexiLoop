/// 词典 provider、合并管线、LLM 降级与每日建议所需的数值常量。
///
/// **为什么不在 `lib/core/constants.dart`**：本批任务的约束明确禁止修改该文件，
/// 而 `lib/domain/` 与 `lib/services/` 又由 `test/architecture` 守卫禁止出现
/// 裸数字字面量（`0`/`1`/`-1` 除外）。两者叠加后，唯一合法的落点是
/// `lib/data/`（守卫不扫描该目录）。
///
/// 这些常量在语义上**属于 `core/constants.dart`**，应在后续提交中整体上移，
/// 上移后本文件即可删除。命名前缀标注了归属模块，便于机械搬迁。
library;

import 'package:lexiloop/core/time.dart';

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

/// 鉴权失败的状态码。
const int httpUnauthorizedStatus = 401;

/// 鉴权被拒的状态码。
const int httpForbiddenStatus = 403;

/// 资源不存在的状态码。
const int httpNotFoundStatus = 404;

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

/// 结构化输出中 JSON Schema 的名字。
const String llmJsonSchemaName = 'lexiloop_lexical_content';
