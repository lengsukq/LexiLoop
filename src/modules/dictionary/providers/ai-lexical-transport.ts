import type { ModelResponse } from "./ai-lexical-schema";
import { JSON_SCHEMA } from "./ai-lexical-schema";
import { normalizeBaseUrl } from "@/lib/url";

function providerError(message: string, status: number): Error & { transient?: boolean; code?: string } {
  const error = new Error(message) as Error & { transient?: boolean; code?: string };
  error.transient = status === 408 || status === 409 || status === 429 || status >= 500;
  error.code = status === 429 ? "RATE_LIMITED" : `HTTP_${status}`;
  return error;
}

export interface AiTransportSettings {
  temperature: number;
  maxOutputTokens: number;
  timeoutMs: number;
  thinkingEnabled?: boolean;
  thinkingBudgetTokens?: number;
  reasoningEffort?: string;
}

function isReasoningModel(model: string): boolean {
  const lower = model.trim().toLowerCase();
  return ["o1", "o3", "gpt-5"].some((prefix) => lower.startsWith(prefix));
}

function shouldRetryWithoutThinking(status: number, message: string): boolean {
  return status === 400 && /thinking|reasoning|reasoning_effort|budget_tokens/i.test(message);
}

export async function requestOpenAiCompatible(providerId: string, baseUrl: string, apiKey: string, model: string, prompt: string, settings: AiTransportSettings): Promise<ModelResponse> {
  const endpoint = `${normalizeBaseUrl(baseUrl)}/chat/completions`;
  const schemaInstruction = `\n\nJSON Schema:\n${JSON.stringify(JSON_SCHEMA)}`;
  const thinkingEnabled = Boolean(settings.thinkingEnabled);
  const budget = Number.isFinite(Number(settings.thinkingBudgetTokens)) ? Math.max(1024, Math.min(20000, Math.round(Number(settings.thinkingBudgetTokens)))) : 4000;
  const reasoningEffort = settings.reasoningEffort?.trim();
  const reasoningModel = isReasoningModel(model);

  const formats = [
    { format: { type: "json_schema", json_schema: { name: "lexiloop_lexical_content", strict: true, schema: JSON_SCHEMA } }, userPrompt: prompt },
    { format: { type: "json_object" }, userPrompt: `${prompt}${schemaInstruction}` },
    { format: null, userPrompt: `${prompt}${schemaInstruction}` },
  ];

  const buildPayload = (withThinking: boolean, withFormat: unknown, userPrompt: string): Record<string, unknown> => {
    const payload: Record<string, unknown> = { model, messages: [{ role: "system", content: "Return only one valid JSON object matching the requested schema." }, { role: "user", content: userPrompt }] };
    if (withThinking && reasoningModel) {
      if (reasoningEffort) payload.reasoning_effort = reasoningEffort;
      else payload.reasoning = { effort: "low" };
      payload.max_completion_tokens = settings.maxOutputTokens;
    } else if (withThinking && reasoningEffort) {
      payload.reasoning_effort = reasoningEffort;
      payload.max_completion_tokens = settings.maxOutputTokens;
    } else {
      payload.temperature = settings.temperature;
      payload.max_tokens = settings.maxOutputTokens;
    }
    if (withFormat) (payload as Record<string, unknown>).response_format = withFormat;
    return payload;
  };

  let lastError = "模型请求失败";
  for (const { format, userPrompt } of formats) {
    const attempt = async (withThinking: boolean): Promise<Response> => fetch(endpoint, {
      method: "POST",
      signal: AbortSignal.timeout(settings.timeoutMs),
      headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` },
      body: JSON.stringify(buildPayload(withThinking, format, userPrompt)),
    });

    let response = await attempt(thinkingEnabled);
    if (!response.ok && thinkingEnabled) {
      const rawPreview = await response.text().catch(() => "");
      if (shouldRetryWithoutThinking(response.status, rawPreview || `HTTP ${response.status}`)) response = await attempt(false);
      else {
        const msg = rawPreview || `HTTP ${response.status}`;
        lastError = msg;
        if (response.status === 400 && format) continue;
        throw providerError(lastError, response.status);
      }
    }
    const body = await response.json().catch(() => null) as Record<string, unknown> | null;
    if (!response.ok) {
      lastError = body && typeof body.error === "object" && body.error ? String((body.error as Record<string, unknown>).message ?? `HTTP ${response.status}`) : `HTTP ${response.status}`;
      if (response.status === 400 && format) continue;
      throw providerError(lastError, response.status);
    }
    return parseOpenAiResponse(providerId, body);
  }
  throw new Error(lastError);
}

function parseOpenAiResponse(providerId: string, body: Record<string, unknown> | null): ModelResponse {
  const choices = Array.isArray(body?.choices) ? body.choices as Array<Record<string, unknown>> : [];
  const choice = choices[0]; const message = choice?.message && typeof choice.message === "object" ? choice.message as Record<string, unknown> : null;
  const content = message?.content;
  const text = typeof content === "string" ? content : Array.isArray(content) ? content.map((item) => typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : "").join("") : content && typeof content === "object" ? JSON.stringify(content) : "";
  const usage = body?.usage && typeof body.usage === "object" ? body.usage as Record<string, unknown> : {};
  if (!text) throw new Error(`${providerId} 返回空内容`);
  return { text, inputTokens: typeof usage.prompt_tokens === "number" ? usage.prompt_tokens : null, outputTokens: typeof usage.completion_tokens === "number" ? usage.completion_tokens : null, finishReason: choice ? String(choice.finish_reason ?? "") || null : null };
}

export async function requestAnthropic(baseUrl: string, apiKey: string, model: string, prompt: string, settings: AiTransportSettings): Promise<ModelResponse> {
  const thinkingEnabled = Boolean(settings.thinkingEnabled);
  const budget = Number.isFinite(Number(settings.thinkingBudgetTokens)) ? Math.max(1024, Math.min(20000, Math.round(Number(settings.thinkingBudgetTokens)))) : 4000;

  const buildBody = (withThinking: boolean): Record<string, unknown> => ({
    model,
    max_tokens: withThinking ? Math.max(settings.maxOutputTokens, budget + settings.maxOutputTokens + 1024) : settings.maxOutputTokens,
    system: "Return only one valid JSON object. Follow the complete schema described by the user.",
    messages: [{ role: "user", content: `${prompt}\n\nJSON Schema:\n${JSON.stringify(JSON_SCHEMA)}` }],
    ...(withThinking ? { thinking: { type: "enabled", budget_tokens: budget }, temperature: 1 } : { temperature: settings.temperature }),
  });

  const attempt = async (withThinking: boolean): Promise<Response> => fetch(`${normalizeBaseUrl(baseUrl)}/messages`, {
    method: "POST",
    signal: AbortSignal.timeout(settings.timeoutMs),
    headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify(buildBody(withThinking)),
  });

  let response = await attempt(thinkingEnabled);
  if (!response.ok && thinkingEnabled) {
    const rawPreview = await response.text().catch(() => "");
    if (shouldRetryWithoutThinking(response.status, rawPreview || `HTTP ${response.status}`)) response = await attempt(false);
    else throw providerError(rawPreview || `HTTP ${response.status}`, response.status);
  }
  const body = await response.json().catch(() => null) as Record<string, unknown> | null;
  if (!response.ok) throw providerError(body && typeof body.error === "object" && body.error ? String((body.error as Record<string, unknown>).message ?? `HTTP ${response.status}`) : `HTTP ${response.status}`, response.status);
  const content = Array.isArray(body?.content) ? body.content as Array<Record<string, unknown>> : [];
  const text = content.map((item) => item.type === "text" ? String(item.text ?? "") : "").join("");
  const usage = body?.usage && typeof body.usage === "object" ? body.usage as Record<string, unknown> : {};
  if (!text) throw new Error("Anthropic 返回空内容");
  return { text, inputTokens: typeof usage.input_tokens === "number" ? usage.input_tokens : null, outputTokens: typeof usage.output_tokens === "number" ? usage.output_tokens : null, finishReason: typeof body?.stop_reason === "string" ? body.stop_reason : null };
}
