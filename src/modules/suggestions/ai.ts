import { getSettings, settingsForAiAttempt } from "@/modules/settings/service";
import { z } from "zod";
import { MINUTE_MS } from "@/lib/time";
import { RECOMMENDATION_LIMIT } from "./content";
import { extractJson } from "@/lib/json";
import { callLlm } from "@/modules/llm/client";
import type {
  AiSuggestionOutput,
  DailySuggestionMetrics,
  GeneratedAiSuggestion,
  SuggestionCandidate,
  SuggestionConfiguration,
} from "./types";

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

function candidatePayload(candidates: SuggestionCandidate[]) {
  return candidates.slice(0, 15).map((candidate) => ({
    wordId: candidate.wordId,
    term: candidate.term,
    currentReason: candidate.reason,
    attemptsYesterday: candidate.attempts,
    incorrectYesterday: candidate.incorrect,
    againYesterday: candidate.again,
    hardYesterday: candidate.hard,
    activeWrongWord: candidate.wrongActive,
    overdueDays: candidate.overdueDays,
    suggestedQuestionType: candidate.questionType,
  }));
}

function buildPrompt(
  metrics: DailySuggestionMetrics,
  qualityScore: number | null,
  candidates: SuggestionCandidate[],
): string {
  return `你是一个英语词汇学习教练。根据昨天的客观学习数据，为今天生成简洁、可执行的中文建议，并从候选词中选择最多 ${RECOMMENDATION_LIMIT} 个今日必做词条。\n\n客观质量分：${qualityScore ?? "无昨日记录"}\n昨日指标：${JSON.stringify(metrics)}\n候选词：${JSON.stringify(candidatePayload(candidates))}\n\n要求：\n1. 不得编造输入中不存在的数据。\n2. 建议必须具体，不要使用空泛鼓励。\n3. recommended 中只能使用候选词里的 wordId。\n4. 输出严格 JSON，不要 Markdown。\n\nJSON 格式：\n{"headline":"一句标题","summary":"昨日回顾和今日重点","strengths":["最多4项"],"risks":["最多4项"],"actions":["2到5项"],"recommended":[{"wordId":1,"reason":"为什么今天必须复习"}]}`;
}

export async function getSuggestionConfiguration(): Promise<SuggestionConfiguration> {
  const settings = await getSettings();
  const purpose = settings.llmConfig.purposes.SUGGESTION;
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  return {
    configured: Boolean(
      purpose.enabled
      && provider?.apiKey.trim()
      && provider.baseUrl.trim()
      && purpose.model.trim(),
    ),
    providerId: provider?.id ?? null,
    model: purpose.model.trim() || null,
  };
}

export async function generateAiSuggestion(
  metrics: DailySuggestionMetrics,
  qualityScore: number | null,
  candidates: SuggestionCandidate[],
  attemptCount = 1,
): Promise<GeneratedAiSuggestion | null> {
  const settings = settingsForAiAttempt(await getSettings(), attemptCount, "SUGGESTION");
  const purpose = settings.llmConfig.purposes.SUGGESTION;
  if (!purpose.enabled) return null;
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) return null;

  const baseUrl = provider.baseUrl.trim().replace(/\/+$/, "");
  const prompt = buildPrompt(metrics, qualityScore, candidates);
  const text = await callLlm(
    { apiType: provider.apiType, baseUrl, apiKey: provider.apiKey, model: purpose.model, timeoutMs: purpose.timeoutMs ?? MINUTE_MS },
    prompt,
    {
      systemPrompt: "只输出有效 JSON。",
      maxOutputTokens: purpose.maxOutputTokens ?? 2000,
      temperature: purpose.temperature ?? 0.2,
      thinkingEnabled: purpose.thinkingEnabled ?? false,
      thinkingBudgetTokens: purpose.thinkingBudgetTokens,
      reasoningEffort: purpose.reasoningEffort,
    },
  );
  if (!text) throw new Error("AI 没有返回建议内容");
  return {
    output: aiOutputSchema.parse(extractJson(text)) as AiSuggestionOutput,
    providerId: provider.id,
    model: purpose.model,
  };
}
