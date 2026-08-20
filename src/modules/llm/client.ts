import { ApiError } from "@/lib/api";
import { formatAiProviderError } from "@/modules/ai-tasks/provider-error";

/** 归一化后的 LLM provider 请求描述，供 `callLlm` 统一发起请求。 */
export interface LlmProviderRequest {
  apiType: "openai" | "anthropic";
  baseUrl: string;
  apiKey: string;
  model: string;
  timeoutMs: number;
}

export interface CallLlmOptions {
  systemPrompt: string;
  /** 不传时使用 `DEFAULT_LLM_MAX_OUTPUT_TOKENS`，避免各调用方硬编码漂移。 */
  maxOutputTokens?: number;
  /** 不传时使用 `DEFAULT_LLM_TEMPERATURE`。 */
  temperature?: number;
}

export const DEFAULT_LLM_MAX_OUTPUT_TOKENS = 2000;
export const DEFAULT_LLM_TEMPERATURE = 0.2;

/** 从 OpenAI / Anthropic 两种响应体里提取文本（空或非对象时返回空串）。 */
function extractText(body: unknown, apiType: "openai" | "anthropic"): string {
  if (!body || typeof body !== "object") return "";
  const record = body as Record<string, unknown>;
  if (apiType === "anthropic") {
    const content = Array.isArray(record.content) ? record.content : [];
    return content
      .map((item) => (typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : ""))
      .join("")
      .trim();
  }
  const choices = Array.isArray(record.choices) ? record.choices as Array<Record<string, unknown>> : [];
  const message = choices[0]?.message;
  const content = message && typeof message === "object" ? (message as Record<string, unknown>).content : null;
  if (typeof content === "string") return content.trim();
  if (Array.isArray(content)) {
    return content
      .map((item) => (typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : ""))
      .join("")
      .trim();
  }
  return "";
}

/**
 * 统一发起 LLM 请求，消除各业务模块里重复的 fetch + 响应解析 + 错误处理。
 * - 成功：返回提取出的模型文本（可能为空，由调用方决定空响应语义）。
 * - 失败（HTTP 非 2xx）：抛 `ApiError("AI_REQUEST_FAILED")`，错误信息经 `formatAiProviderError` 归一化。
 */
export async function callLlm(provider: LlmProviderRequest, userPrompt: string, options: CallLlmOptions): Promise<string> {
  const baseUrl = provider.baseUrl.trim().replace(/\/+$/, "");
  const maxOutputTokens = options.maxOutputTokens ?? DEFAULT_LLM_MAX_OUTPUT_TOKENS;
  const temperature = options.temperature ?? DEFAULT_LLM_TEMPERATURE;

  const response = provider.apiType === "anthropic"
    ? await fetch(`${baseUrl}/messages`, {
        method: "POST",
        signal: AbortSignal.timeout(provider.timeoutMs),
        headers: {
          "content-type": "application/json",
          "x-api-key": provider.apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: provider.model,
          max_tokens: maxOutputTokens,
          temperature,
          system: options.systemPrompt,
          messages: [{ role: "user", content: userPrompt }],
        }),
      })
    : await fetch(`${baseUrl}/chat/completions`, {
        method: "POST",
        signal: AbortSignal.timeout(provider.timeoutMs),
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${provider.apiKey}`,
        },
        body: JSON.stringify({
          model: provider.model,
          messages: [
            { role: "system", content: options.systemPrompt },
            { role: "user", content: userPrompt },
          ],
          temperature,
          max_tokens: maxOutputTokens,
        }),
      });

  const raw = await response.text().catch(() => "");
  if (!response.ok) throw new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, raw), 502);

  let body: unknown = null;
  try {
    body = JSON.parse(raw);
  } catch {
    // 调用方根据自身 Schema 决定如何处置无效/空响应。
  }
  return extractText(body, provider.apiType);
}
