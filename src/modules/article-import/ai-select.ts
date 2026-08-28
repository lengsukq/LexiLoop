import { callLlmWithFallback, resolveLlmProviders } from "@/modules/llm/client";
import { getSettings } from "@/modules/settings/service";
import type { VocabularyLevel } from "@/lib/types";
import { buildArticleSelectionPrompt, parseJsonLoose } from "./prompt";
import { aiSelectionResponseSchema } from "./schema";

export interface AiSelectInput {
  articleText: string;
  candidates: Array<{ term: string; normalizedTerm: string; occurrences: number }>;
  knownSample: string[];
  totalKnown: number;
  vocabularyLevel: VocabularyLevel;
}

export interface AiSelectResult {
  applied: boolean;
  selected: Array<{ term: string; reason: string; difficulty: number; cefrLevel: string | null; frequency: string | null }>;
  error?: string;
}

export async function aiSelectTerms(input: AiSelectInput): Promise<AiSelectResult> {
  const settings = await getSettings();
  const { primary, fallback } = resolveLlmProviders(settings);
  if (!primary) {
    const purpose = settings.llmConfig.ai;
    if (!purpose?.enabled) return { applied: false, selected: [], error: "AI 未启用，请到设置页开启 AI。" };
    return { applied: false, selected: [], error: "AI 服务配置不完整，请到设置页补全。" };
  }
  const purpose = settings.llmConfig.ai;

  const { systemPrompt, userPrompt } = buildArticleSelectionPrompt({
    articleText: input.articleText,
    candidates: input.candidates,
    knownSample: input.knownSample,
    totalKnown: input.totalKnown,
    vocabularyLevel: input.vocabularyLevel,
  });

  let raw = "";
  try {
    raw = await callLlmWithFallback(primary, fallback, userPrompt, {
      systemPrompt,
      maxOutputTokens: purpose.maxOutputTokens ?? 3000,
      temperature: purpose.temperature ?? 0.2,
      thinkingEnabled: purpose.thinkingEnabled ?? false,
      thinkingBudgetTokens: purpose.thinkingBudgetTokens,
      reasoningEffort: purpose.reasoningEffort,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "AI 请求失败";
    return { applied: false, selected: [], error: message };
  }

  const parsed = parseJsonLoose(raw);
  if (!parsed) return { applied: false, selected: [], error: "AI 返回内容不是有效 JSON，已回退为本地筛选。" };

  const result = aiSelectionResponseSchema.safeParse(parsed);
  if (!result.success) return { applied: false, selected: [], error: "AI 返回格式不符合预期，已回退为本地筛选。" };

  const selected = result.data.selected.map((item) => ({
    term: item.term,
    reason: item.reason,
    difficulty: item.difficulty,
    cefrLevel: item.cefrLevel ?? null,
    frequency: item.frequency ?? null,
  }));

  return { applied: true, selected };
}
