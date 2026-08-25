import { ApiError } from "@/lib/api";
import { callLlm } from "@/modules/llm/client";
import { getSettings, settingsForAiAttempt } from "@/modules/settings/service";
import { tencentTranslateBatch, TencentTranslateError, type TencentTranslateConfig } from "@/lib/tencent-translate-client";
import { z } from "zod";

export class TranslationServiceError extends ApiError { constructor(code: string, message: string, status: number) { super(code, message, status); } }
export interface TranslationItem { index: number; sentence: string; }
const outputSchema = z.object({ translations: z.array(z.object({ index: z.number().int().nonnegative(), translation: z.string().trim().min(1).max(2000) })).max(50) }).strict();

type ProviderConfig = { apiType: "openai" | "anthropic"; baseUrl: string; apiKey: string; model: string; timeoutMs: number; providerId: string; thinkingEnabled?: boolean; thinkingBudgetTokens?: number; reasoningEffort?: string };

async function getProvider(attemptCount: number): Promise<ProviderConfig> {
  const settings = settingsForAiAttempt(await getSettings(), attemptCount);
  const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  if (!purpose.enabled) throw new ApiError("AI_DISABLED");
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) throw new ApiError("AI_CONFIG_INCOMPLETE");
  return {
    apiType: provider.apiType, baseUrl: provider.baseUrl, apiKey: provider.apiKey, model: purpose.model, timeoutMs: purpose.timeoutMs ?? 30_000, providerId: provider.id,
    thinkingEnabled: purpose.thinkingEnabled ?? false, thinkingBudgetTokens: purpose.thinkingBudgetTokens, reasoningEffort: purpose.reasoningEffort,
  };
}
async function getTencent(): Promise<TencentTranslateConfig | null> { const settings = await getSettings(); if (!settings.tencentTranslateEnabled || !settings.tencentTranslateSecretId.trim() || !settings.tencentTranslateSecretKey.trim()) return null; return { secretId: settings.tencentTranslateSecretId.trim(), secretKey: settings.tencentTranslateSecretKey.trim(), projectId: settings.tencentTranslateProjectId }; }
async function requestAi(provider: ProviderConfig, targetLanguage: string, items: TranslationItem[]): Promise<Map<number, string>> {
  const prompt = `你是严谨的语言学习翻译助手。把下面每条源语言内容翻译成 ${targetLanguage}。\n要求：翻译自然、准确、适合背单词；只输出 JSON：{"translations":[{"index":0,"translation":"翻译"}]}。\n${JSON.stringify(items)}`;
  const text = await callLlm(provider, prompt, {
    systemPrompt: "Return only one valid JSON object. Do not use Markdown.",
    maxOutputTokens: 2000, temperature: 0.2,
    thinkingEnabled: provider.thinkingEnabled, thinkingBudgetTokens: provider.thinkingBudgetTokens, reasoningEffort: provider.reasoningEffort,
  });
  if (!text.trim()) throw new TranslationServiceError("AI_EMPTY_RESPONSE", "AI 没有返回翻译内容。", 422);
  let parsed: z.infer<typeof outputSchema>; try { parsed = outputSchema.parse(JSON.parse(text.trim().replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, ""))); } catch { throw new TranslationServiceError("AI_RESPONSE_INVALID", "AI 返回的翻译格式无效，请重试或更换模型。", 422); }
  const allowed = new Set(items.map((item) => item.index)); return new Map(parsed.translations.filter((item) => allowed.has(item.index)).map((item) => [item.index, item.translation]));
}
export async function translateItems(items: TranslationItem[], sourceLanguage: string, targetLanguage: string, attemptCount: number): Promise<{ translations: Map<number, string>; sourceId: string }> {
  const tencent = await getTencent(); if (tencent) { try { const translations = await tencentTranslateBatch(items, sourceLanguage, targetLanguage, tencent); if (translations.size) return { translations, sourceId: "tencent-translate" }; } catch (error) { if (error instanceof TencentTranslateError && error.status === 429) throw error; } }
  const provider = await getProvider(attemptCount); return { translations: await requestAi(provider, targetLanguage, items), sourceId: provider.providerId };
}
