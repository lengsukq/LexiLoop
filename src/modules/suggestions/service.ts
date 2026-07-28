import { sqlite } from "@/db/client";
import type { QuestionType } from "@/lib/types";
import { formatAiProviderError } from "@/modules/ai-tasks/provider-error";
import { getSettings } from "@/modules/settings/service";
import { z } from "zod";

const timezone = process.env.APP_TIMEZONE ?? "Asia/Shanghai";
const DAY_MS = 24 * 60 * 60 * 1000;
const RECOMMENDATION_LIMIT = 8;
const VALID_QUESTION_TYPES = new Set<QuestionType>(["EN_TO_ZH", "EN_TO_ZH_CHOICE", "ZH_TO_EN_SPELLING", "LISTENING_SPELLING"]);

export interface DailySuggestionMetrics {
  reviewCount: number;
  correctCount: number;
  accuracy: number | null;
  againCount: number;
  hardCount: number;
  skippedCount: number;
  sessionCount: number;
  averageDurationMs: number | null;
  studyMinutes: number;
  completionRate: number | null;
  questionAccuracy: Record<string, number | null>;
}

export interface RecommendedStudyItem {
  wordId: number;
  term: string;
  definition: string | null;
  reason: string;
  questionType: QuestionType;
  score: number;
}

export interface DailyAiSuggestion {
  dateKey: string;
  sourceDateKey: string;
  qualityScore: number | null;
  metrics: DailySuggestionMetrics;
  headline: string;
  summary: string;
  strengths: string[];
  risks: string[];
  actions: string[];
  recommendedItems: RecommendedStudyItem[];
  generator: "AI" | "RULE_BASED";
  configured: boolean;
  providerId: string | null;
  model: string | null;
  generationWarning: string | null;
  generatedAt: string;
}

type ReviewRow = {
  word_id: number;
  reviewed_at: number;
  rating: string;
  question_type: string;
  is_correct: number;
  duration_ms: number | null;
  study_session_id: number | null;
};

type CandidateAccumulator = {
  wordId: number;
  attempts: number;
  incorrect: number;
  again: number;
  hard: number;
  durationTotal: number;
  durationCount: number;
  questionErrors: Map<string, number>;
  wrongActive: boolean;
  wrongCount: number;
  hardCount: number;
  dueAt: number | null;
  difficulty: number;
  lapses: number;
  fallback: boolean;
};

type Candidate = RecommendedStudyItem & {
  attempts: number;
  incorrect: number;
  again: number;
  hard: number;
  wrongActive: boolean;
  overdueDays: number;
};

const aiOutputSchema = z.object({
  headline: z.string().trim().min(1).max(80),
  summary: z.string().trim().min(1).max(500),
  strengths: z.array(z.string().trim().min(1).max(160)).max(4),
  risks: z.array(z.string().trim().min(1).max(160)).max(4),
  actions: z.array(z.string().trim().min(1).max(160)).min(1).max(5),
  recommended: z.array(z.object({
    wordId: z.number().int().positive(),
    reason: z.string().trim().min(1).max(160),
  })).max(10),
}).passthrough();

type AiOutput = z.infer<typeof aiOutputSchema>;
const generationInFlight = new Map<string, Promise<DailyAiSuggestion>>();

export function suggestionDateKey(timestamp: number): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(timestamp));
}

function parseJson<T>(value: unknown, fallback: T): T {
  if (typeof value !== "string") return (value ?? fallback) as T;
  try { return JSON.parse(value) as T; } catch { return fallback; }
}

function clamp(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

function previousDateKey(now: number): string {
  return suggestionDateKey(now - DAY_MS);
}

function collectMetrics(now: number, sourceDateKey: string): { metrics: DailySuggestionMetrics; reviews: ReviewRow[] } {
  const since = now - 3 * DAY_MS;
  const allReviews = sqlite.prepare(`SELECT word_id, reviewed_at, rating, question_type, is_correct, duration_ms, study_session_id
    FROM review_logs WHERE reviewed_at >= ? ORDER BY reviewed_at ASC`).all(since) as ReviewRow[];
  const reviews = allReviews.filter((row) => suggestionDateKey(row.reviewed_at) === sourceDateKey);
  const skips = (sqlite.prepare(`SELECT answered_at FROM study_session_items
    WHERE status = 'SKIPPED' AND COALESCE(skip_reason, '') NOT IN ('SESSION_EXPIRED', 'PROGRESS_RESET')
      AND answered_at >= ?`).all(since) as Array<{ answered_at: number }>)
    .filter((row) => suggestionDateKey(row.answered_at) === sourceDateKey);
  const sessions = (sqlite.prepare(`SELECT started_at, duration_ms, completed_count FROM study_sessions
    WHERE started_at >= ?`).all(since) as Array<{ started_at: number; duration_ms: number | null; completed_count: number }>)
    .filter((row) => suggestionDateKey(row.started_at) === sourceDateKey && row.completed_count > 0);

  const correctCount = reviews.filter((row) => Boolean(row.is_correct)).length;
  const durationRows = reviews.filter((row) => row.duration_ms !== null && row.duration_ms! >= 0);
  const sessionDuration = sessions.reduce((sum, row) => sum + (row.duration_ms ?? 0), 0);
  const standaloneDuration = reviews.filter((row) => row.study_session_id === null).reduce((sum, row) => sum + (row.duration_ms ?? 0), 0);
  const questionGroups = new Map<string, { total: number; correct: number }>();
  for (const row of reviews) {
    const group = questionGroups.get(row.question_type) ?? { total: 0, correct: 0 };
    group.total += 1;
    if (row.is_correct) group.correct += 1;
    questionGroups.set(row.question_type, group);
  }
  return {
    reviews,
    metrics: {
      reviewCount: reviews.length,
      correctCount,
      accuracy: reviews.length ? Math.round(correctCount / reviews.length * 100) : null,
      againCount: reviews.filter((row) => row.rating === "AGAIN").length,
      hardCount: reviews.filter((row) => row.rating === "HARD").length,
      skippedCount: skips.length,
      sessionCount: sessions.length,
      averageDurationMs: durationRows.length
        ? Math.round(durationRows.reduce((sum, row) => sum + (row.duration_ms ?? 0), 0) / durationRows.length)
        : null,
      studyMinutes: Math.round((sessionDuration + standaloneDuration) / 60_000),
      completionRate: reviews.length + skips.length ? Math.round(reviews.length / (reviews.length + skips.length) * 100) : null,
      questionAccuracy: Object.fromEntries([...questionGroups.entries()].map(([key, value]) => [key, value.total ? Math.round(value.correct / value.total * 100) : null])),
    },
  };
}

function qualityScore(metrics: DailySuggestionMetrics): number | null {
  if (!metrics.reviewCount || metrics.accuracy === null) return null;
  const challengePenalty = (metrics.againCount * 1.5 + metrics.hardCount * 0.7) / metrics.reviewCount;
  const stability = clamp(100 - challengePenalty * 55, 0, 100);
  const speed = metrics.averageDurationMs === null
    ? 70
    : clamp(100 - Math.max(0, metrics.averageDurationMs - 5_000) / 180, 35, 100);
  const completion = metrics.completionRate ?? 70;
  return Math.round(metrics.accuracy * 0.58 + stability * 0.2 + speed * 0.08 + completion * 0.14);
}

function candidateAccumulator(map: Map<number, CandidateAccumulator>, wordId: number): CandidateAccumulator {
  let value = map.get(wordId);
  if (!value) {
    value = {
      wordId,
      attempts: 0,
      incorrect: 0,
      again: 0,
      hard: 0,
      durationTotal: 0,
      durationCount: 0,
      questionErrors: new Map(),
      wrongActive: false,
      wrongCount: 0,
      hardCount: 0,
      dueAt: null,
      difficulty: 0,
      lapses: 0,
      fallback: false,
    };
    map.set(wordId, value);
  }
  return value;
}

function mostUsefulQuestion(item: CandidateAccumulator): QuestionType {
  const weakQuestion = [...item.questionErrors.entries()].sort((left, right) => right[1] - left[1])[0]?.[0];
  if (weakQuestion && VALID_QUESTION_TYPES.has(weakQuestion as QuestionType)) return weakQuestion as QuestionType;
  if (item.wrongActive || item.incorrect > 0) return "ZH_TO_EN_SPELLING";
  return "EN_TO_ZH";
}

function buildReason(item: CandidateAccumulator, now: number): string {
  const parts: string[] = [];
  if (item.incorrect > 0) parts.push(`昨天答错 ${item.incorrect} 次`);
  if (item.again > 0) parts.push(`${item.again} 次选择忘记`);
  if (item.hard > 0) parts.push(`${item.hard} 次感觉模糊`);
  if (item.wrongActive && item.incorrect === 0) parts.push("仍在错词队列中");
  if (item.dueAt !== null && item.dueAt <= now) {
    const overdue = Math.max(0, Math.floor((now - item.dueAt) / DAY_MS));
    parts.push(overdue > 0 ? `已逾期 ${overdue} 天` : "今天到期");
  }
  if (!parts.length) parts.push("基础掌握度较低，建议优先巩固");
  return parts.slice(0, 2).join("，");
}

function candidateScore(item: CandidateAccumulator, now: number): number {
  const averageDuration = item.durationCount ? item.durationTotal / item.durationCount : 0;
  const overdueDays = item.dueAt !== null && item.dueAt <= now ? Math.max(0, (now - item.dueAt) / DAY_MS) : 0;
  return Math.round(
    item.incorrect * 120
    + item.again * 75
    + item.hard * 38
    + (item.wrongActive ? 55 : 0)
    + item.wrongCount * 7
    + item.hardCount * 4
    + Math.min(45, Math.max(0, averageDuration - 7_000) / 300)
    + (item.dueAt !== null && item.dueAt <= now ? 22 : 0)
    + Math.min(35, overdueDays * 4)
    + item.difficulty * 2
    + item.lapses * 5
    + (item.fallback ? 1 : 0)
  );
}

function preferredDefinition(raw: string | null, targetLanguage: string): string | null {
  const definitions = parseJson<Array<{ language?: string; text?: string }>>(raw, []);
  return definitions.find((item) => item.language === targetLanguage)?.text
    ?? definitions.find((item) => item.text)?.text
    ?? null;
}

function buildCandidates(now: number, reviews: ReviewRow[]): Candidate[] {
  const map = new Map<number, CandidateAccumulator>();
  for (const row of reviews) {
    const item = candidateAccumulator(map, row.word_id);
    item.attempts += 1;
    if (!row.is_correct) {
      item.incorrect += 1;
      item.questionErrors.set(row.question_type, (item.questionErrors.get(row.question_type) ?? 0) + 1);
    }
    if (row.rating === "AGAIN") item.again += 1;
    if (row.rating === "HARD") item.hard += 1;
    if (row.duration_ms !== null) {
      item.durationTotal += row.duration_ms;
      item.durationCount += 1;
    }
  }

  const wrongRows = sqlite.prepare(`SELECT word_id, wrong_count, hard_count FROM wrong_word_states
    WHERE active = 1 ORDER BY updated_at ASC LIMIT 200`).all() as Array<{ word_id: number; wrong_count: number; hard_count: number }>;
  for (const row of wrongRows) {
    const item = candidateAccumulator(map, row.word_id);
    item.wrongActive = true;
    item.wrongCount = row.wrong_count;
    item.hardCount = row.hard_count;
  }

  const dueRows = sqlite.prepare(`SELECT word_id, due_at, difficulty, lapses FROM review_cards
    WHERE due_at <= ? ORDER BY due_at ASC LIMIT 200`).all(now) as Array<{ word_id: number; due_at: number; difficulty: number; lapses: number }>;
  for (const row of dueRows) {
    const item = candidateAccumulator(map, row.word_id);
    item.dueAt = row.due_at;
    item.difficulty = row.difficulty;
    item.lapses = row.lapses;
  }

  const isRiskCandidate = (item: CandidateAccumulator) => item.incorrect > 0
    || item.again > 0
    || item.hard > 0
    || item.wrongActive
    || (item.dueAt !== null && item.dueAt <= now)
    || item.fallback;
  if (![...map.values()].some(isRiskCandidate)) {
    const fallbackRows = sqlite.prepare(`SELECT w.id FROM words w
      WHERE w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      ORDER BY w.mastery_score ASC, COALESCE(w.source_created_at, w.created_at) ASC LIMIT 12`).all() as Array<{ id: number }>;
    for (const row of fallbackRows) candidateAccumulator(map, row.id).fallback = true;
  }

  const ranked = [...map.values()].filter(isRiskCandidate)
    .sort((left, right) => candidateScore(right, now) - candidateScore(left, now)).slice(0, 30);
  if (!ranked.length) return [];
  const placeholders = ranked.map(() => "?").join(",");
  const rows = sqlite.prepare(`SELECT w.id, w.term, w.target_language, wc.definitions_json
    FROM words w LEFT JOIN word_contents wc ON wc.word_id = w.id
    WHERE w.id IN (${placeholders}) AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')`).all(...ranked.map((item) => item.wordId)) as Array<{
      id: number; term: string; target_language: string; definitions_json: string | null;
    }>;
  const words = new Map(rows.map((row) => [row.id, row]));
  return ranked.flatMap((item) => {
    const word = words.get(item.wordId);
    if (!word) return [];
    const score = candidateScore(item, now);
    return [{
      wordId: item.wordId,
      term: word.term,
      definition: preferredDefinition(word.definitions_json, word.target_language),
      reason: buildReason(item, now),
      questionType: mostUsefulQuestion(item),
      score,
      attempts: item.attempts,
      incorrect: item.incorrect,
      again: item.again,
      hard: item.hard,
      wrongActive: item.wrongActive,
      overdueDays: item.dueAt !== null && item.dueAt <= now ? Math.max(0, Math.floor((now - item.dueAt) / DAY_MS)) : 0,
    } satisfies Candidate];
  });
}

function ruleBasedContent(metrics: DailySuggestionMetrics, candidates: Candidate[]) {
  if (!metrics.reviewCount) {
    return {
      headline: "今天先恢复学习节奏",
      summary: "昨天没有可分析的答题记录。今天建议先完成少量高优先级复习，再逐步恢复每日学习量。",
      strengths: [] as string[],
      risks: ["连续中断会让到期词条继续积压"],
      actions: ["先完成 AI 必做题", "再处理到期复习", "今天保持一次完整学习会话"],
    };
  }
  const accuracy = metrics.accuracy ?? 0;
  const headline = accuracy >= 85 ? "保持状态，做一次精准巩固" : accuracy >= 65 ? "重点修复昨天的薄弱词" : "今天先稳住正确率";
  const strengths = [
    ...(accuracy >= 80 ? [`昨天正确率达到 ${accuracy}%`] : []),
    ...(metrics.completionRate !== null && metrics.completionRate >= 90 ? ["昨日任务完成度较好"] : []),
  ];
  const risks = [
    ...(accuracy < 70 ? [`昨天正确率仅 ${accuracy}%，需要减少新词并加强复习`] : []),
    ...(metrics.againCount > 0 ? [`有 ${metrics.againCount} 题选择“忘记”`] : []),
    ...(metrics.skippedCount > 0 ? [`跳过了 ${metrics.skippedCount} 题`] : []),
  ];
  const actions = [
    candidates.length ? `优先完成 ${Math.min(RECOMMENDATION_LIMIT, candidates.length)} 道必做题` : "先完成到期复习",
    accuracy < 75 ? "今天减少新词数量，把时间用于错词拼写" : "保持当前新词量",
    metrics.averageDurationMs !== null && metrics.averageDurationMs > 15_000 ? "答题偏慢，先回忆再查看答案" : "复习时重点确认最容易混淆的含义",
  ];
  return {
    headline,
    summary: `昨天完成 ${metrics.reviewCount} 次作答，正确率 ${accuracy}%，学习约 ${metrics.studyMinutes} 分钟。今天的重点是先处理高风险词，再继续常规队列。`,
    strengths,
    risks,
    actions,
  };
}

function extractJson(text: string): unknown {
  const trimmed = text.trim();
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
  return JSON.parse(fenced ? fenced[1]! : trimmed);
}

function responseText(payload: unknown, apiType: "openai" | "anthropic"): string {
  if (!payload || typeof payload !== "object") return "";
  const body = payload as Record<string, unknown>;
  if (apiType === "anthropic") {
    const content = Array.isArray(body.content) ? body.content : [];
    return content.map((item) => typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : "").join("").trim();
  }
  const choices = Array.isArray(body.choices) ? body.choices as Array<Record<string, unknown>> : [];
  const message = choices[0]?.message;
  const content = message && typeof message === "object" ? (message as Record<string, unknown>).content : null;
  if (typeof content === "string") return content.trim();
  if (Array.isArray(content)) return content.map((item) => typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : "").join("").trim();
  return "";
}

async function suggestionConfiguration(): Promise<{ configured: boolean; providerId: string | null; model: string | null }> {
  const settings = await getSettings();
  const purpose = settings.llmConfig.purposes.SUGGESTION;
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  return {
    configured: Boolean(purpose.enabled && provider?.apiKey.trim() && provider.baseUrl.trim() && purpose.model.trim()),
    providerId: provider?.id ?? null,
    model: purpose.model.trim() || null,
  };
}

async function generateAiContent(metrics: DailySuggestionMetrics, score: number | null, candidates: Candidate[]): Promise<{
  output: AiOutput;
  providerId: string;
  model: string;
} | null> {
  const settings = await getSettings();
  const purpose = settings.llmConfig.purposes.SUGGESTION;
  if (!purpose.enabled) return null;
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) return null;

  const candidatePayload = candidates.slice(0, 15).map((item) => ({
    wordId: item.wordId,
    term: item.term,
    currentReason: item.reason,
    attemptsYesterday: item.attempts,
    incorrectYesterday: item.incorrect,
    againYesterday: item.again,
    hardYesterday: item.hard,
    activeWrongWord: item.wrongActive,
    overdueDays: item.overdueDays,
    suggestedQuestionType: item.questionType,
  }));
  const prompt = `你是一个英语词汇学习教练。根据昨天的客观学习数据，为今天生成简洁、可执行的中文建议，并从候选词中选择最多 ${RECOMMENDATION_LIMIT} 个今日必做词条。\n\n客观质量分：${score ?? "无昨日记录"}\n昨日指标：${JSON.stringify(metrics)}\n候选词：${JSON.stringify(candidatePayload)}\n\n要求：\n1. 不得编造输入中不存在的数据。\n2. 建议必须具体，不要使用空泛鼓励。\n3. recommended 中只能使用候选词里的 wordId。\n4. 输出严格 JSON，不要 Markdown。\n\nJSON 格式：\n{"headline":"一句标题","summary":"昨日回顾和今日重点","strengths":["最多4项"],"risks":["最多4项"],"actions":["2到5项"],"recommended":[{"wordId":1,"reason":"为什么今天必须复习"}]}`;
  const baseUrl = provider.baseUrl.trim().replace(/\/+$/, "");
  const timeout = purpose.timeoutMs ?? 60_000;
  const response = provider.apiType === "anthropic"
    ? await fetch(`${baseUrl}/messages`, {
        method: "POST",
        signal: AbortSignal.timeout(timeout),
        headers: { "content-type": "application/json", "x-api-key": provider.apiKey, "anthropic-version": "2023-06-01" },
        body: JSON.stringify({ model: purpose.model, max_tokens: purpose.maxOutputTokens ?? 2000, temperature: purpose.temperature ?? 0.2, system: "只输出有效 JSON。", messages: [{ role: "user", content: prompt }] }),
      })
    : await fetch(`${baseUrl}/chat/completions`, {
        method: "POST",
        signal: AbortSignal.timeout(timeout),
        headers: { "content-type": "application/json", authorization: `Bearer ${provider.apiKey}` },
        body: JSON.stringify({ model: purpose.model, messages: [{ role: "system", content: "只输出有效 JSON。" }, { role: "user", content: prompt }], temperature: purpose.temperature ?? 0.2, max_tokens: purpose.maxOutputTokens ?? 2000 }),
      });
  const raw = await response.text().catch(() => "");
  if (!response.ok) throw new Error(formatAiProviderError(response.status, raw));
  let payload: unknown = null;
  try { payload = JSON.parse(raw); } catch { throw new Error("AI 响应不是有效 JSON 包装"); }
  const text = responseText(payload, provider.apiType);
  if (!text) throw new Error("AI 没有返回建议内容");
  return { output: aiOutputSchema.parse(extractJson(text)), providerId: provider.id, model: purpose.model };
}

function orderRecommended(candidates: Candidate[], ai: AiOutput | null): RecommendedStudyItem[] {
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

function cachedSuggestion(dateKey: string): DailyAiSuggestion | null {
  const row = sqlite.prepare("SELECT * FROM daily_ai_suggestions WHERE date_key = ?").get(dateKey) as Record<string, unknown> | undefined;
  if (!row) return null;
  const content = parseJson<{ headline: string; summary: string; strengths: string[]; risks: string[]; actions: string[] }>(row.content_json, {
    headline: "今日学习建议",
    summary: "",
    strengths: [],
    risks: [],
    actions: [],
  });
  const configured = Boolean(row.generator === "AI" || row.provider_id);
  return {
    dateKey: String(row.date_key),
    sourceDateKey: String(row.source_date_key),
    qualityScore: row.quality_score === null ? null : Number(row.quality_score),
    metrics: parseJson<DailySuggestionMetrics>(row.metrics_json, {
      reviewCount: 0, correctCount: 0, accuracy: null, againCount: 0, hardCount: 0, skippedCount: 0,
      sessionCount: 0, averageDurationMs: null, studyMinutes: 0, completionRate: null, questionAccuracy: {},
    }),
    headline: content.headline,
    summary: content.summary,
    strengths: content.strengths ?? [],
    risks: content.risks ?? [],
    actions: content.actions ?? [],
    recommendedItems: parseJson<RecommendedStudyItem[]>(row.recommended_items_json, []),
    generator: row.generator === "AI" ? "AI" : "RULE_BASED",
    configured,
    providerId: row.provider_id ? String(row.provider_id) : null,
    model: row.model ? String(row.model) : null,
    generationWarning: row.generation_warning ? String(row.generation_warning) : null,
    generatedAt: new Date(Number(row.generated_at)).toISOString(),
  };
}

async function generateSuggestion(now: number, dateKey: string): Promise<DailyAiSuggestion> {
  const sourceDateKey = previousDateKey(now);
  const { metrics, reviews } = collectMetrics(now, sourceDateKey);
  const score = qualityScore(metrics);
  const candidates = buildCandidates(now, reviews);
  const fallback = ruleBasedContent(metrics, candidates);
  let ai: Awaited<ReturnType<typeof generateAiContent>> = null;
  let warning: string | null = null;
  try {
    ai = await generateAiContent(metrics, score, candidates);
  } catch (error) {
    warning = error instanceof Error ? error.message : String(error);
  }
  const recommendedItems = orderRecommended(candidates, ai?.output ?? null);
  const content = ai?.output ? {
    headline: ai.output.headline,
    summary: ai.output.summary,
    strengths: ai.output.strengths,
    risks: ai.output.risks,
    actions: ai.output.actions,
  } : fallback;
  const config = await suggestionConfiguration();
  const generatedAt = Date.now();
  sqlite.prepare(`INSERT INTO daily_ai_suggestions
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
      dateKey,
      sourceDateKey,
      score,
      JSON.stringify(metrics),
      JSON.stringify(content),
      JSON.stringify(recommendedItems),
      ai ? "AI" : "RULE_BASED",
      ai?.providerId ?? config.providerId,
      ai?.model ?? config.model,
      warning,
      generatedAt,
      generatedAt,
    );
  const saved = cachedSuggestion(dateKey);
  if (!saved) throw new Error("DAILY_SUGGESTION_SAVE_FAILED");
  saved.configured = ai ? true : config.configured;
  return saved;
}

export async function getTodaySuggestion(options: { force?: boolean; now?: number } = {}): Promise<DailyAiSuggestion> {
  const now = options.now ?? Date.now();
  const dateKey = suggestionDateKey(now);
  if (!options.force) {
    const cached = cachedSuggestion(dateKey);
    if (cached) {
      cached.configured = (await suggestionConfiguration()).configured;
      return cached;
    }
  }
  const existing = generationInFlight.get(dateKey);
  if (existing) return existing;
  const promise = generateSuggestion(now, dateKey).finally(() => generationInFlight.delete(dateKey));
  generationInFlight.set(dateKey, promise);
  return promise;
}

export async function getTodayRecommendedItems(): Promise<RecommendedStudyItem[]> {
  return (await getTodaySuggestion()).recommendedItems;
}
