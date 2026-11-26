/**
 * @deprecated 直接使用 `src/modules/llm/client.ts` 的 `callLlm`。
 * 为保持 `AiLexicalProvider` 的零成本迁移，本文件仅作薄转发层。
 */
import { callLlm } from "@/modules/llm/client";
import { JSON_SCHEMA, type ModelResponse } from "./ai-lexical-schema";

export type { ModelResponse } from "./ai-lexical-schema";

export interface AiTransportSettings {
  temperature: number;
  maxOutputTokens: number;
  timeoutMs: number;
  thinkingEnabled?: boolean;
  thinkingBudgetTokens?: number;
  reasoningEffort?: string;
}

export async function requestOpenAiCompatible(
  providerId: string,
  baseUrl: string,
  apiKey: string,
  model: string,
  prompt: string,
  settings: AiTransportSettings,
): Promise<ModelResponse> {
  const response = await callLlm(
    { apiType: "openai", baseUrl, apiKey, model, timeoutMs: settings.timeoutMs },
    prompt,
    {
      systemPrompt: "Return only one valid JSON object matching the requested schema.",
      maxOutputTokens: settings.maxOutputTokens,
      temperature: settings.temperature,
      thinkingEnabled: settings.thinkingEnabled,
      thinkingBudgetTokens: settings.thinkingBudgetTokens,
      reasoningEffort: settings.reasoningEffort,
      jsonSchema: JSON_SCHEMA,
      returnMetadata: true,
    },
  );
  if (!response.text) throw new Error(`${providerId} 返回空内容`);
  return response;
}

export async function requestAnthropic(
  baseUrl: string,
  apiKey: string,
  model: string,
  prompt: string,
  settings: AiTransportSettings,
): Promise<ModelResponse> {
  const response = await callLlm(
    { apiType: "anthropic", baseUrl, apiKey, model, timeoutMs: settings.timeoutMs },
    prompt,
    {
      systemPrompt: "Return only one valid JSON object. Follow the complete schema described by the user.",
      maxOutputTokens: settings.maxOutputTokens,
      temperature: settings.temperature,
      thinkingEnabled: settings.thinkingEnabled,
      thinkingBudgetTokens: settings.thinkingBudgetTokens,
      reasoningEffort: settings.reasoningEffort,
      jsonSchema: JSON_SCHEMA,
      returnMetadata: true,
    },
  );
  if (!response.text) throw new Error("Anthropic 返回空内容");
  return response;
}
