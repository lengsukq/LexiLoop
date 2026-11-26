import { buildSuggestionCandidates } from "./candidates";
import { orderRecommendedItems, ruleBasedSuggestion } from "./content";
import { previousSuggestionDateKey, suggestionDateKey } from "./date";
import { calculateQualityScore, collectSuggestionMetrics } from "./metrics";
import { findCachedSuggestion, saveSuggestion } from "./repository";
import type { DailyAiSuggestion, RecommendedStudyItem } from "./types";

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
  const content = ruleBasedSuggestion(metrics, candidates);

  return saveSuggestion({
    dateKey,
    sourceDateKey,
    qualityScore,
    metrics,
    content,
    recommendedItems: orderRecommendedItems(candidates, null),
    generator: "RULE_BASED",
    configuration: { configured: false, providerId: null, model: null },
    providerId: null,
    model: null,
    warning: null,
  });
}

export async function getTodaySuggestion(
  options: { force?: boolean; now?: number } = {},
): Promise<DailyAiSuggestion> {
  const now = options.now ?? Date.now();
  const dateKey = suggestionDateKey(now);
  if (!options.force) {
    const cached = await findCachedSuggestion(dateKey);
    if (cached) return cached;
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
