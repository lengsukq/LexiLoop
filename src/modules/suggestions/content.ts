import type {
  AiSuggestionOutput,
  DailySuggestionMetrics,
  RecommendedStudyItem,
  SuggestionCandidate,
  SuggestionContent,
} from "./types";

export const RECOMMENDATION_LIMIT = 8;

export function ruleBasedSuggestion(
  metrics: DailySuggestionMetrics,
  candidates: SuggestionCandidate[],
): SuggestionContent {
  if (!metrics.reviewCount) {
    return {
      headline: "今天先恢复学习节奏",
      summary: "昨天没有可分析的答题记录。今天建议先完成少量高优先级复习，再逐步恢复每日学习量。",
      strengths: [],
      risks: ["连续中断会让到期词条继续积压"],
      actions: ["先完成 AI 必做题", "再处理到期复习", "今天保持一次完整学习会话"],
    };
  }

  const accuracy = metrics.accuracy ?? 0;
  return {
    headline: accuracy >= 85
      ? "保持状态，做一次精准巩固"
      : accuracy >= 65
        ? "重点修复昨天的薄弱词"
        : "今天先稳住正确率",
    summary: `昨天完成 ${metrics.reviewCount} 次作答，正确率 ${accuracy}%，学习约 ${metrics.studyMinutes} 分钟。今天的重点是先处理高风险词，再继续常规队列。`,
    strengths: [
      ...(accuracy >= 80 ? [`昨天正确率达到 ${accuracy}%`] : []),
      ...(metrics.completionRate !== null && metrics.completionRate >= 90 ? ["昨日任务完成度较好"] : []),
    ],
    risks: [
      ...(accuracy < 70 ? [`昨天正确率仅 ${accuracy}%，需要减少新词并加强复习`] : []),
      ...(metrics.againCount > 0 ? [`有 ${metrics.againCount} 题选择“忘记”`] : []),
      ...(metrics.skippedCount > 0 ? [`跳过了 ${metrics.skippedCount} 题`] : []),
    ],
    actions: [
      candidates.length ? `优先完成 ${Math.min(RECOMMENDATION_LIMIT, candidates.length)} 道必做题` : "先完成到期复习",
      accuracy < 75 ? "今天减少新词数量，把时间用于错词拼写" : "保持当前新词量",
      metrics.averageDurationMs !== null && metrics.averageDurationMs > 15_000
        ? "答题偏慢，先回忆再查看答案"
        : "复习时重点确认最容易混淆的含义",
    ],
  };
}

export function orderRecommendedItems(
  candidates: SuggestionCandidate[],
  ai: AiSuggestionOutput | null,
): RecommendedStudyItem[] {
  const byId = new Map(candidates.map((candidate) => [candidate.wordId, candidate]));
  const selected: RecommendedStudyItem[] = [];
  const seen = new Set<number>();

  for (const item of ai?.recommended ?? []) {
    const candidate = byId.get(item.wordId);
    if (!candidate || seen.has(candidate.wordId)) continue;
    seen.add(candidate.wordId);
    selected.push({ ...candidate, reason: item.reason });
    if (selected.length >= RECOMMENDATION_LIMIT) return selected;
  }
  for (const candidate of candidates) {
    if (seen.has(candidate.wordId)) continue;
    seen.add(candidate.wordId);
    selected.push(candidate);
    if (selected.length >= RECOMMENDATION_LIMIT) break;
  }
  return selected;
}
