import type { ModelResponse } from "./ai-lexical-schema";
import { JSON_SCHEMA } from "./ai-lexical-schema";
import { normalizeBaseUrl } from "@/lib/url";

function providerError(message: string, status: number): Error & { transient?: boolean; code?: string } {
  const error = new Error(message) as Error & { transient?: boolean; code?: string };
  error.transient = status === 408 || status === 409 || status === 429 || status >= 500;
  error.code = status === 429 ? "RATE_LIMITED" : `HTTP_${status}`;
  return error;
}

export async function requestOpenAiCompatible(providerId: string, baseUrl: string, apiKey: string, model: string, prompt: string, settings: { temperature: number; maxOutputTokens: number; timeoutMs: number }): Promise<ModelResponse> {
  const endpoint = `${normalizeBaseUrl(baseUrl)}/chat/completions`;
  const schemaInstruction = `\n\nJSON Schema:\n${JSON.stringify(JSON_SCHEMA)}`;
  const formats = [
    { format: { type: "json_schema", json_schema: { name: "lexiloop_lexical_content", strict: true, schema: JSON_SCHEMA } }, userPrompt: prompt },
    { format: { type: "json_object" }, userPrompt: `${prompt}${schemaInstruction}` },
    { format: null, userPrompt: `${prompt}${schemaInstruction}` },
  ];
  let lastError = "模型请求失败";
  for (const { format, userPrompt } of formats) {
    const response = await fetch(endpoint, { method: "POST", signal: AbortSignal.timeout(settings.timeoutMs), headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` }, body: JSON.stringify({ model, messages: [{ role: "system", content: "Return only one valid JSON object matching the requested schema." }, { role: "user", content: userPrompt }], temperature: settings.temperature, ...(format ? { response_format: format } : {}) }) });
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

export async function requestAnthropic(baseUrl: string, apiKey: string, model: string, prompt: string, settings: { temperature: number; maxOutputTokens: number; timeoutMs: number }): Promise<ModelResponse> {
  const response = await fetch(`${normalizeBaseUrl(baseUrl)}/messages`, { method: "POST", signal: AbortSignal.timeout(settings.timeoutMs), headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" }, body: JSON.stringify({ model, max_tokens: settings.maxOutputTokens, temperature: settings.temperature, system: "Return only one valid JSON object. Follow the complete schema described by the user.", messages: [{ role: "user", content: `${prompt}\n\nJSON Schema:\n${JSON.stringify(JSON_SCHEMA)}` }] }) });
  const body = await response.json().catch(() => null) as Record<string, unknown> | null;
  if (!response.ok) throw providerError(body && typeof body.error === "object" && body.error ? String((body.error as Record<string, unknown>).message ?? `HTTP ${response.status}`) : `HTTP ${response.status}`, response.status);
  const content = Array.isArray(body?.content) ? body.content as Array<Record<string, unknown>> : [];
  const text = content.map((item) => item.type === "text" ? String(item.text ?? "") : "").join("");
  const usage = body?.usage && typeof body.usage === "object" ? body.usage as Record<string, unknown> : {};
  if (!text) throw new Error("Anthropic 返回空内容");
  return { text, inputTokens: typeof usage.input_tokens === "number" ? usage.input_tokens : null, outputTokens: typeof usage.output_tokens === "number" ? usage.output_tokens : null, finishReason: typeof body?.stop_reason === "string" ? body.stop_reason : null };
}
