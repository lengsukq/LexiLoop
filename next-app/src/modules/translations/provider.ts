import { ApiError } from "@/lib/api";
import { callLlmWithFallback, resolveLlmProviders } from "@/modules/llm/client";
import { getSettings } from "@/modules/settings/service";
import { tencentTranslateBatch, TencentTranslateError, type TencentTranslateConfig } from "@/lib/tencent-translate-client";
import { z } from "zod";

export class TranslationServiceError extends ApiError {
  constructor(code: string, message: string, status: number) {
    super(code, message, status);
  }
}
export interface TranslationItem {
  index: number;
  sentence: string;
}
const outputSchema = z
  .object({ translations: z.array(z.object({ index: z.number().int().nonnegative(), translation: z.string().trim().min(1).max(2000) })).max(50) })
  .strict();

async function getTencent(): Promise<TencentTranslateConfig | null> {
  const settings = await getSettings();
  if (!settings.tencentTranslateEnabled || !settings.tencentTranslateSecretId.trim() || !settings.tencentTranslateSecretKey.trim()) return null;
  return {
    secretId: settings.tencentTranslateSecretId.trim(),
    secretKey: settings.tencentTranslateSecretKey.trim(),
    projectId: settings.tencentTranslateProjectId,
  };
}
async function requestAi(targetLanguage: string, items: TranslationItem[]): Promise<Map<number, string>> {
  const settings = await getSettings();
  const { primary, fallback } = resolveLlmProviders(settings);
  if (!primary) {
    const purpose = settings.llmConfig.ai;
    if (!purpose.enabled) throw new ApiError("AI_DISABLED");
    throw new ApiError("AI_CONFIG_INCOMPLETE");
  }
  const purpose = settings.llmConfig.ai;
  const prompt = `你是严谨的语言学习翻译助手。把下面每条源语言内容翻译成 ${targetLanguage}。\n要求：翻译自然、准确、适合背单词；只输出 JSON：{"translations":[{"index":0,"translation":"翻译"}]}。\n${JSON.stringify(items)}`;
  const text = await callLlmWithFallback(primary, fallback, prompt, {
    systemPrompt: "Return only one valid JSON object. Do not use Markdown.",
    maxOutputTokens: 2000,
    temperature: 0.2,
    thinkingEnabled: purpose.thinkingEnabled,
    thinkingBudgetTokens: purpose.thinkingBudgetTokens,
    reasoningEffort: purpose.reasoningEffort,
  });
  if (!text.trim()) throw new TranslationServiceError("AI_EMPTY_RESPONSE", "AI 没有返回翻译内容。", 422);
  let parsed: z.infer<typeof outputSchema>;
  try {
    parsed = outputSchema.parse(JSON.parse(text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "")));
  } catch {
    throw new TranslationServiceError("AI_RESPONSE_INVALID", "AI 返回的翻译格式无效，请重试或更换模型。", 422);
  }
  const allowed = new Set(items.map((item) => item.index));
  return new Map(parsed.translations.filter((item) => allowed.has(item.index)).map((item) => [item.index, item.translation]));
}
export async function translateItems(
  items: TranslationItem[],
  sourceLanguage: string,
  targetLanguage: string,
): Promise<{ translations: Map<number, string>; sourceId: string }> {
  const tencent = await getTencent();
  if (tencent) {
    try {
      const translations = await tencentTranslateBatch(items, sourceLanguage, targetLanguage, tencent);
      if (translations.size) return { translations, sourceId: "tencent-translate" };
    } catch (error) {
      if (error instanceof TencentTranslateError && error.status === 429) throw error;
    }
  }
  const settings = await getSettings();
  const { primary } = resolveLlmProviders(settings);
  const sourceId = primary ? (settings.llmConfig.providers.find((p) => p.id === settings.llmConfig.ai.providerId)?.id ?? primary.model) : "ai";
  // Re-resolve inside requestAi for actual provider selection; keep sourceId consistent with primary
  const translations = await requestAi(targetLanguage, items);
  return { translations, sourceId };
}
