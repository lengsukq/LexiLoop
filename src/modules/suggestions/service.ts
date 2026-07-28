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
  const { metrics, reviews } = collectSuggestionMetrics(now, sourceDateKey);
  const qualityScore = calculateQualityScore(metrics);
  const candidates = buildSuggestionCandidates(now, reviews);
  const fallback = ruleBasedSuggestion(metrics, candidates);
  let ai: Awaited<ReturnType<typeof generateAiSuggestion>> = null;
  let warning: string | null = null;

  try {
    ai = await generateAiSuggestion(metrics, qualityScore, candidates);
  } catch (error) {
    warning = error instanceof Error ? error.message : String(error);
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
    const cached = findCachedSuggestion(dateKey);
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
