import { generateAiSuggestion, getSuggestionConfiguration } from "./ai";
import { buildSuggestionCandidates } from "./candidates";
import { orderRecommendedItems, ruleBasedSuggestion } from "./content";
import { previousSuggestionDateKey, suggestionDateKey } from "./date";
import { calculateQualityScore, collectSuggestionMetrics } from "./metrics";
import { findCachedSuggestion, saveSuggestion } from "./repository";
import type { DailyAiSuggestion, RecommendedStudyItem, SuggestionContent } from "./types";

export type {
  DailyAiSuggestion,
  DailySuggestionMetrics,
  RecommendedStudyItem,
} from "./types";
export { suggestionDateKey } from "./date";

const generationInFlight = new Map<string, Promise<DailyAiSuggestion>>();

async function generateSuggestion(now: number, dateKey: string): Promise<DailyAiSuggestion> {
  const sourceDateKey = previousSuggestionDateKey(now);
  const { metrics, reviews } = await collectSuggestionMetrics(now, sourceDateKey);
  const qualityScore = calculateQualityScore(metrics);
  const candidates = await buildSuggestionCandidates(now, reviews);
  const fallback = ruleBasedSuggestion(metrics, candidates);
  let ai: Awaited<ReturnType<typeof generateAiSuggestion>> = null;
  let warning: string | null = null;

  for (const attemptCount of [1, 2]) {
    try {
      ai = await generateAiSuggestion(metrics, qualityScore, candidates, attemptCount);
      if (ai) {
        warning = null;
        break;
      }
      if (attemptCount === 1) break;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      warning = attemptCount === 1 ? `首次调用失败：${message}` : `重试后仍失败：${message}`;
      if (attemptCount === 2) break;
    }
  }

  const content: SuggestionContent = ai ? {
    headline: ai.output.headline,
    summary: ai.output.summary,
    strengths: ai.output.strengths,
    risks: ai.output.risks,
    actions: ai.output.actions,
  } : fallback;
  const configuration = await getSuggestionConfiguration();

  return saveSuggestion({
    dateKey,
    sourceDateKey,
    qualityScore,
    metrics,
    content,
    recommendedItems: orderRecommendedItems(candidates, ai?.output ?? null),
    generator: ai ? "AI" : "RULE_BASED",
    configuration,
    providerId: ai?.providerId ?? null,
    model: ai?.model ?? null,
    warning,
  });
}

export async function getTodaySuggestion(
  options: { force?: boolean; now?: number } = {},
): Promise<DailyAiSuggestion> {
  const now = options.now ?? Date.now();
  const dateKey = suggestionDateKey(now);
  if (!options.force) {
    const cached = await findCachedSuggestion(dateKey);
    if (cached) {
      cached.configured = (await getSuggestionConfiguration()).configured;
      return cached;
    }
  }

  const existing = generationInFlight.get(dateKey);
  if (existing) return existing;
  const promise = generateSuggestion(now, dateKey)
    .finally(() => generationInFlight.delete(dateKey));
  generationInFlight.set(dateKey, promise);
  return promise;
}

export async function getTodayRecommendedItems(): Promise<RecommendedStudyItem[]> {
  return (await getTodaySuggestion()).recommendedItems;
}
