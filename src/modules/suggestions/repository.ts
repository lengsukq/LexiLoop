import { sqlite } from "@/db/client";
import { parseJson } from "@/lib/json";
import type {
  DailyAiSuggestion,
  DailySuggestionMetrics,
  RecommendedStudyItem,
  SuggestionConfiguration,
  SuggestionContent,
} from "./types";

const EMPTY_METRICS: DailySuggestionMetrics = {
  reviewCount: 0,
  correctCount: 0,
  accuracy: null,
  againCount: 0,
  hardCount: 0,
  skippedCount: 0,
  sessionCount: 0,
  averageDurationMs: null,
  studyMinutes: 0,
  completionRate: null,
  questionAccuracy: {},
};

const EMPTY_CONTENT: SuggestionContent = {
  headline: "今日学习建议",
  summary: "",
  strengths: [],
  risks: [],
  actions: [],
};

export async function findCachedSuggestion(dateKey: string): Promise<DailyAiSuggestion | null> {
  const row = await sqlite.prepare("SELECT * FROM daily_ai_suggestions WHERE date_key = ?")
    .get(dateKey) as Record<string, unknown> | undefined;
  if (!row) return null;
  const content = parseJson<SuggestionContent>(row.content_json, EMPTY_CONTENT);

  return {
    dateKey: String(row.date_key),
    sourceDateKey: String(row.source_date_key),
    qualityScore: row.quality_score === null ? null : Number(row.quality_score),
    metrics: parseJson<DailySuggestionMetrics>(row.metrics_json, EMPTY_METRICS),
    headline: content.headline,
    summary: content.summary,
    strengths: content.strengths ?? [],
    risks: content.risks ?? [],
    actions: content.actions ?? [],
    recommendedItems: parseJson<RecommendedStudyItem[]>(row.recommended_items_json, []),
    generator: row.generator === "AI" ? "AI" : "RULE_BASED",
    configured: Boolean(row.generator === "AI" || row.provider_id),
    providerId: row.provider_id ? String(row.provider_id) : null,
    model: row.model ? String(row.model) : null,
    generationWarning: row.generation_warning ? String(row.generation_warning) : null,
    generatedAt: new Date(Number(row.generated_at)).toISOString(),
  };
}

export async function saveSuggestion(input: {
  dateKey: string;
  sourceDateKey: string;
  qualityScore: number | null;
  metrics: DailySuggestionMetrics;
  content: SuggestionContent;
  recommendedItems: RecommendedStudyItem[];
  generator: "AI" | "RULE_BASED";
  configuration: SuggestionConfiguration;
  providerId: string | null;
  model: string | null;
  warning: string | null;
}): Promise<DailyAiSuggestion> {
  const generatedAt = Date.now();
  await sqlite.prepare(`INSERT INTO daily_ai_suggestions
    (date_key, source_date_key, quality_score, metrics_json, content_json, recommended_items_json,
     generator, provider_id, model, generation_warning, generated_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(date_key) DO UPDATE SET
      source_date_key = excluded.source_date_key,
      quality_score = excluded.quality_score,
      metrics_json = excluded.metrics_json,
      content_json = excluded.content_json,
      recommended_items_json = excluded.recommended_items_json,
      generator = excluded.generator,
      provider_id = excluded.provider_id,
      model = excluded.model,
      generation_warning = excluded.generation_warning,
      generated_at = excluded.generated_at,
      updated_at = excluded.updated_at`)
    .run(
      input.dateKey,
      input.sourceDateKey,
      input.qualityScore,
      JSON.stringify(input.metrics),
      JSON.stringify(input.content),
      JSON.stringify(input.recommendedItems),
      input.generator,
      input.providerId ?? input.configuration.providerId,
      input.model ?? input.configuration.model,
      input.warning,
      generatedAt,
      generatedAt,
    );

  const saved = await findCachedSuggestion(input.dateKey);
  if (!saved) throw new Error("DAILY_SUGGESTION_SAVE_FAILED");
  saved.configured = input.generator === "AI" || input.configuration.configured;
  return saved;
}
