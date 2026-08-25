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
  thinkingEnabled?: boolean;
  thinkingBudgetTokens?: number;
  reasoningEffort?: string;
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
 * - 思考默认关闭，仅当 `thinkingEnabled` 显式开启时才发送思考参数，避免 Vercel 免费版超时。
 */
export async function callLlm(provider: LlmProviderRequest, userPrompt: string, options: CallLlmOptions): Promise<string> {
  const baseUrl = provider.baseUrl.trim().replace(/\/+$/, "");
  const maxOutputTokens = options.maxOutputTokens ?? DEFAULT_LLM_MAX_OUTPUT_TOKENS;
  const temperature = options.temperature ?? DEFAULT_LLM_TEMPERATURE;
  const thinkingEnabled = Boolean(options.thinkingEnabled);
  const thinkingBudgetTokens = Number.isFinite(Number(options.thinkingBudgetTokens)) ? Math.max(1024, Math.min(20000, Math.round(Number(options.thinkingBudgetTokens)))) : 4000;
  const reasoningEffort = options.reasoningEffort?.trim();

  const isReasoningModel = (() => {
    const lower = provider.model.trim().toLowerCase();
    return ["o1", "o3", "gpt-5"].some((prefix) => lower.startsWith(prefix));
  })();

  const shouldRetryWithoutThinking = (status: number, message: string): boolean => status === 400 && /thinking|reasoning|reasoning_effort|budget_tokens/i.test(message);

  const buildAnthropicBody = (withThinking: boolean): Record<string, unknown> => {
    const payload: Record<string, unknown> = {
      model: provider.model,
      max_tokens: withThinking ? Math.max(maxOutputTokens, thinkingBudgetTokens + maxOutputTokens + 1024) : maxOutputTokens,
      system: options.systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
    };
    if (withThinking) {
      payload.thinking = { type: "enabled", budget_tokens: thinkingBudgetTokens };
      payload.temperature = 1;
    } else payload.temperature = temperature;
    return payload;
  };

  const buildOpenAiBody = (withThinking: boolean): Record<string, unknown> => {
    const payload: Record<string, unknown> = {
      model: provider.model,
      messages: [
        { role: "system", content: options.systemPrompt },
        { role: "user", content: userPrompt },
      ],
    };
    if (withThinking && isReasoningModel) {
      if (reasoningEffort) payload.reasoning_effort = reasoningEffort;
      else payload.reasoning = { effort: "low" };
      payload.max_completion_tokens = maxOutputTokens;
    } else if (withThinking && reasoningEffort) {
      payload.reasoning_effort = reasoningEffort;
      payload.max_completion_tokens = maxOutputTokens;
    } else {
      payload.temperature = temperature;
      payload.max_tokens = maxOutputTokens;
    }
    return payload;
  };

  const sendAnthropic = async (withThinking: boolean): Promise<Response> => fetch(`${baseUrl}/messages`, {
    method: "POST",
    signal: AbortSignal.timeout(provider.timeoutMs),
    headers: { "content-type": "application/json", "x-api-key": provider.apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify(buildAnthropicBody(withThinking)),
  });

  const sendOpenAi = async (withThinking: boolean): Promise<Response> => fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    signal: AbortSignal.timeout(provider.timeoutMs),
    headers: { "content-type": "application/json", authorization: `Bearer ${provider.apiKey}` },
    body: JSON.stringify(buildOpenAiBody(withThinking)),
  });

  let response: Response;
  let rawPreview = "";

  if (provider.apiType === "anthropic") {
    response = await sendAnthropic(thinkingEnabled);
    if (!response.ok && thinkingEnabled) {
      rawPreview = await response.text().catch(() => "");
      if (shouldRetryWithoutThinking(response.status, rawPreview || `HTTP ${response.status}`)) response = await sendAnthropic(false);
      else throw new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, rawPreview), 502);
      rawPreview = "";
    }
    if (!response.ok) {
      const raw = rawPreview || await response.text().catch(() => "");
      throw new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, raw), 502);
    }
    const raw = await response.text().catch(() => "");
    let body: unknown = null;
    try { body = JSON.parse(raw); } catch { /* empty */ }
    return extractText(body, provider.apiType);
  }

  response = await sendOpenAi(thinkingEnabled);
  if (!response.ok && thinkingEnabled) {
    rawPreview = await response.text().catch(() => "");
    if (shouldRetryWithoutThinking(response.status, rawPreview || `HTTP ${response.status}`)) response = await sendOpenAi(false);
    else throw new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, rawPreview), 502);
    rawPreview = "";
  }
  if (!response.ok) {
    const raw = rawPreview || await response.text().catch(() => "");
    throw new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, raw), 502);
  }
  const raw = await response.text().catch(() => "");
  let body: unknown = null;
  try { body = JSON.parse(raw); } catch { /* empty */ }
  return extractText(body, provider.apiType);
}
