import { ApiError } from "@/lib/api";
import { normalizeBaseUrl } from "@/lib/url";
import { formatAiProviderError } from "@/modules/ai-tasks/provider-error";
import type { AppSettings } from "@/lib/types";

/** 归一化后的 LLM provider 请求描述，供 `callLlm` 统一发起请求。 */
export interface LlmProviderRequest {
  apiType: "openai" | "anthropic";
  baseUrl: string;
  apiKey: string;
  model: string;
  timeoutMs: number;
}

export interface ModelResponse {
  text: string;
  inputTokens: number | null;
  outputTokens: number | null;
  finishReason: string | null;
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
  /** 结构化输出：传入 JSON Schema 时走 json_schema → json_object → 无约束的 3 档降级（仅 OpenAI）。 */
  jsonSchema?: object;
  /** 为真时返回含 token/finishReason 的 ModelResponse，否则返回 string。 */
  returnMetadata?: boolean;
}

export const DEFAULT_LLM_MAX_OUTPUT_TOKENS = 2000;
export const DEFAULT_LLM_TEMPERATURE = 0.2;

function clampBudget(value: unknown): number {
  const num = Number(value);
  if (!Number.isFinite(num)) return 4000;
  return Math.max(1024, Math.min(20000, Math.round(num)));
}

function isReasoningModel(model: string): boolean {
  const lower = model.trim().toLowerCase();
  return ["o1", "o3", "gpt-5"].some((prefix) => lower.startsWith(prefix));
}

function shouldRetryWithoutThinking(status: number, message: string): boolean {
  return status === 400 && /thinking|reasoning|reasoning_effort|budget_tokens/i.test(message);
}

function isTransientStatus(status: number): boolean {
  return status === 408 || status === 409 || status === 429 || status >= 500;
}

function isTimeoutError(error: unknown): boolean {
  return error instanceof DOMException && error.name === "TimeoutError";
}

function attachTransient(error: ApiError, status: number, timeout: boolean): void {
  (error as ApiError & { transient?: boolean; originalStatus?: number }).transient = timeout || isTransientStatus(status);
  (error as ApiError & { transient?: boolean; originalStatus?: number }).originalStatus = status;
}

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
  const choices = Array.isArray(record.choices) ? (record.choices as Array<Record<string, unknown>>) : [];
  const message = choices[0]?.message;
  const content = message && typeof message === "object" ? (message as Record<string, unknown>).content : null;
  if (typeof content === "string") return content.trim();
  if (Array.isArray(content)) {
    return content
      .map((item) => (typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : ""))
      .join("")
      .trim();
  }
  if (content && typeof content === "object") return JSON.stringify(content).trim();
  return "";
}

function parseOpenAiResponse(body: Record<string, unknown> | null): ModelResponse {
  const choices = Array.isArray(body?.choices) ? (body?.choices as Array<Record<string, unknown>>) : [];
  const choice = choices[0];
  const message = choice?.message && typeof choice.message === "object" ? (choice.message as Record<string, unknown>) : null;
  const content = message?.content;
  const text =
    typeof content === "string"
      ? content
      : Array.isArray(content)
        ? content.map((item) => (typeof item === "object" && item ? String((item as Record<string, unknown>).text ?? "") : "")).join("")
        : content && typeof content === "object"
          ? JSON.stringify(content)
          : "";
  const usage = body?.usage && typeof body.usage === "object" ? (body.usage as Record<string, unknown>) : {};
  return {
    text: text.trim(),
    inputTokens: typeof usage.prompt_tokens === "number" ? usage.prompt_tokens : null,
    outputTokens: typeof usage.completion_tokens === "number" ? usage.completion_tokens : null,
    finishReason: choice ? String(choice.finish_reason ?? "") || null : null,
  };
}

function parseAnthropicResponse(body: Record<string, unknown> | null): ModelResponse {
  const content = Array.isArray(body?.content) ? (body.content as Array<Record<string, unknown>>) : [];
  const text = content.map((item) => (item.type === "text" ? String(item.text ?? "") : "")).join("");
  const usage = body?.usage && typeof body.usage === "object" ? (body.usage as Record<string, unknown>) : {};
  return {
    text: text.trim(),
    inputTokens: typeof usage.input_tokens === "number" ? usage.input_tokens : null,
    outputTokens: typeof usage.output_tokens === "number" ? usage.output_tokens : null,
    finishReason: typeof body?.stop_reason === "string" ? body.stop_reason : null,
  };
}

/**
 * 统一发起 LLM 请求，消除各业务模块里重复的 fetch + 响应解析 + 错误处理。
 * - 成功：返回提取出的模型文本（可能为空，由调用方决定空响应语义）；returnMetadata=true 时返回 ModelResponse。
 * - 失败（HTTP 非 2xx / 网络超时）：抛 `ApiError("AI_REQUEST_FAILED")`，错误信息经 `formatAiProviderError` 归一化，并附 `transient` 标记供 fallback 使用。
 * - 思考默认关闭，仅当 `thinkingEnabled` 显式开启时才发送思考参数，避免 Vercel 免费版超时。
 * - 传入 `jsonSchema` 时（词典初始化）自动走结构化输出 3 档降级。
 */
export async function callLlm(provider: LlmProviderRequest, userPrompt: string, options: CallLlmOptions & { returnMetadata: true }): Promise<ModelResponse>;
export async function callLlm(provider: LlmProviderRequest, userPrompt: string, options: CallLlmOptions): Promise<string>;
export async function callLlm(
  provider: LlmProviderRequest,
  userPrompt: string,
  options: CallLlmOptions,
): Promise<string | ModelResponse> {
  const baseUrl = normalizeBaseUrl(provider.baseUrl);
  const maxOutputTokens = options.maxOutputTokens ?? DEFAULT_LLM_MAX_OUTPUT_TOKENS;
  const temperature = options.temperature ?? DEFAULT_LLM_TEMPERATURE;
  const thinkingEnabled = Boolean(options.thinkingEnabled);
  const thinkingBudgetTokens = clampBudget(options.thinkingBudgetTokens);
  const reasoningEffort = options.reasoningEffort?.trim();
  const isReasoning = isReasoningModel(provider.model);

  const buildAnthropicBody = (withThinking: boolean, prompt: string): Record<string, unknown> => {
    const payload: Record<string, unknown> = {
      model: provider.model,
      max_tokens: withThinking ? Math.max(maxOutputTokens, thinkingBudgetTokens + maxOutputTokens + 1024) : maxOutputTokens,
      system: options.systemPrompt,
      messages: [{ role: "user", content: prompt }],
    };
    if (withThinking) {
      payload.thinking = { type: "enabled", budget_tokens: thinkingBudgetTokens };
      payload.temperature = 1;
    } else payload.temperature = temperature;
    return payload;
  };

  const buildOpenAiBody = (withThinking: boolean, withFormat: unknown, prompt: string): Record<string, unknown> => {
    const payload: Record<string, unknown> = {
      model: provider.model,
      messages: [
        { role: "system", content: options.systemPrompt },
        { role: "user", content: prompt },
      ],
    };
    if (withThinking && isReasoning) {
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
    if (withFormat) (payload as Record<string, unknown>).response_format = withFormat;
    return payload;
  };

  // Anthropic path
  if (provider.apiType === "anthropic") {
    const schemaInstruction = options.jsonSchema ? `\n\nJSON Schema:\n${JSON.stringify(options.jsonSchema)}` : "";
    const finalPrompt = `${userPrompt}${schemaInstruction}`;

    const attempt = async (withThinking: boolean): Promise<Response> => {
      try {
        return await fetch(`${baseUrl}/messages`, {
          method: "POST",
          signal: AbortSignal.timeout(provider.timeoutMs),
          headers: { "content-type": "application/json", "x-api-key": provider.apiKey, "anthropic-version": "2023-06-01" },
          body: JSON.stringify(buildAnthropicBody(withThinking, finalPrompt)),
        });
      } catch (error) {
        if (isTimeoutError(error)) {
          const apiErr = new ApiError("AI_REQUEST_FAILED", "AI 请求超时", 502);
          (apiErr as unknown as Record<string, unknown>).transient = true;
          throw apiErr;
        }
        const apiErr = new ApiError("AI_REQUEST_FAILED", String(error), 502);
        (apiErr as unknown as Record<string, unknown>).transient = true;
        throw apiErr;
      }
    };

    let response = await attempt(thinkingEnabled);
    if (!response.ok && thinkingEnabled) {
      const rawPreview = await response.text().catch(() => "");
      if (shouldRetryWithoutThinking(response.status, rawPreview || `HTTP ${response.status}`)) {
        response = await attempt(false);
      } else {
        const apiErr = new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, rawPreview), 502);
        attachTransient(apiErr, response.status, false);
        throw apiErr;
      }
    }
    if (!response.ok) {
      const raw = await response.text().catch(() => "");
      const apiErr = new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, raw), 502);
      attachTransient(apiErr, response.status, false);
      throw apiErr;
    }
    const raw = await response.text().catch(() => "");
    let body: unknown = null;
    try {
      body = JSON.parse(raw);
    } catch {
      /* empty */
    }
    if (options.returnMetadata) return parseAnthropicResponse(body as Record<string, unknown> | null);
    return extractText(body, "anthropic");
  }

  // OpenAI path — with structured output loop when jsonSchema is provided
  if (options.jsonSchema) {
    const schemaInstruction = `\n\nJSON Schema:\n${JSON.stringify(options.jsonSchema)}`;
    const formats: Array<{ format: unknown; prompt: string }> = [
      { format: { type: "json_schema", json_schema: { name: "lexiloop_lexical_content", strict: true, schema: options.jsonSchema } }, prompt: userPrompt },
      { format: { type: "json_object" }, prompt: `${userPrompt}${schemaInstruction}` },
      { format: null, prompt: `${userPrompt}${schemaInstruction}` },
    ];

    let lastError = "模型请求失败";
    for (const { format, prompt } of formats) {
      const attempt = async (withThinking: boolean): Promise<Response> => {
        try {
          return await fetch(`${baseUrl}/chat/completions`, {
            method: "POST",
            signal: AbortSignal.timeout(provider.timeoutMs),
            headers: { "content-type": "application/json", authorization: `Bearer ${provider.apiKey}` },
            body: JSON.stringify(buildOpenAiBody(withThinking, format, prompt)),
          });
        } catch (error) {
          if (isTimeoutError(error)) {
            const apiErr = new ApiError("AI_REQUEST_FAILED", "AI 请求超时", 502);
            (apiErr as unknown as Record<string, unknown>).transient = true;
            throw apiErr;
          }
          const apiErr = new ApiError("AI_REQUEST_FAILED", String(error), 502);
          (apiErr as unknown as Record<string, unknown>).transient = true;
          throw apiErr;
        }
      };

      let response: Response;
      try {
        response = await attempt(thinkingEnabled);
      } catch (e) {
        throw e;
      }

      if (!response.ok && thinkingEnabled) {
        const rawPreview = await response.text().catch(() => "");
        if (shouldRetryWithoutThinking(response.status, rawPreview || `HTTP ${response.status}`)) {
          try {
            response = await attempt(false);
          } catch (e) {
            throw e;
          }
        } else {
          lastError = rawPreview || `HTTP ${response.status}`;
          if (response.status === 400 && format) continue;
          const apiErr = new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, rawPreview), 502);
          attachTransient(apiErr, response.status, false);
          throw apiErr;
        }
      }

      // Need raw text for body parsing, but preserve status check
      const rawText = await response.text().catch(() => "");
      let body: unknown = null;
      try {
        body = JSON.parse(rawText);
      } catch {
        /* empty */
      }
      if (!response.ok) {
        const msg =
          body && typeof body === "object" && body
            ? (() => {
                const rec = body as Record<string, unknown>;
                const errObj = rec.error;
                if (errObj && typeof errObj === "object") return String((errObj as Record<string, unknown>).message ?? `HTTP ${response.status}`);
                return `HTTP ${response.status}`;
              })()
            : `HTTP ${response.status}`;
        lastError = msg;
        if (response.status === 400 && format) continue;
        const apiErr = new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, rawText), 502);
        attachTransient(apiErr, response.status, false);
        throw apiErr;
      }

      if (options.returnMetadata) {
        const parsed = parseOpenAiResponse(body as Record<string, unknown> | null);
        if (!parsed.text) {
          const apiErr = new ApiError("AI_REQUEST_FAILED", "返回空内容", 502);
          (apiErr as unknown as Record<string, unknown>).transient = false;
          throw apiErr;
        }
        return parsed;
      }
      return extractText(body, "openai");
    }
    const apiErr = new ApiError("AI_REQUEST_FAILED", lastError, 502);
    (apiErr as unknown as Record<string, unknown>).transient = false;
    throw apiErr;
  }

  // OpenAI non-structured single attempt
  {
    const attempt = async (withThinking: boolean): Promise<Response> => {
      try {
        return await fetch(`${baseUrl}/chat/completions`, {
          method: "POST",
          signal: AbortSignal.timeout(provider.timeoutMs),
          headers: { "content-type": "application/json", authorization: `Bearer ${provider.apiKey}` },
          body: JSON.stringify(buildOpenAiBody(withThinking, null, userPrompt)),
        });
      } catch (error) {
        if (isTimeoutError(error)) {
          const apiErr = new ApiError("AI_REQUEST_FAILED", "AI 请求超时", 502);
          (apiErr as unknown as Record<string, unknown>).transient = true;
          throw apiErr;
        }
        const apiErr = new ApiError("AI_REQUEST_FAILED", String(error), 502);
        (apiErr as unknown as Record<string, unknown>).transient = true;
        throw apiErr;
      }
    };

    let response = await attempt(thinkingEnabled);
    if (!response.ok && thinkingEnabled) {
      const rawPreview = await response.text().catch(() => "");
      if (shouldRetryWithoutThinking(response.status, rawPreview || `HTTP ${response.status}`)) {
        response = await attempt(false);
      } else {
        const apiErr = new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, rawPreview), 502);
        attachTransient(apiErr, response.status, false);
        throw apiErr;
      }
    }
    if (!response.ok) {
      const raw = await response.text().catch(() => "");
      const apiErr = new ApiError("AI_REQUEST_FAILED", formatAiProviderError(response.status, raw), 502);
      attachTransient(apiErr, response.status, false);
      throw apiErr;
    }
    const raw = await response.text().catch(() => "");
    let body: unknown = null;
    try {
      body = JSON.parse(raw);
    } catch {
      /* empty */
    }
    if (options.returnMetadata) return parseOpenAiResponse(body as Record<string, unknown> | null);
    return extractText(body, "openai");
  }
}

/**
 * 同一次请求内的主备自动切换：主失败且为可重试错误时立即用备用重发。
 * 仅 transient（超时/网络/429/5xx/408/409）会触发切换，避免把鉴权/格式错误误切到备用上浪费配额。
 */
export async function callLlmWithFallback(
  primary: LlmProviderRequest,
  fallback: LlmProviderRequest | null | undefined,
  userPrompt: string,
  options: CallLlmOptions & { returnMetadata: true },
): Promise<ModelResponse>;
export async function callLlmWithFallback(
  primary: LlmProviderRequest,
  fallback: LlmProviderRequest | null | undefined,
  userPrompt: string,
  options: CallLlmOptions,
): Promise<string>;
export async function callLlmWithFallback(
  primary: LlmProviderRequest,
  fallback: LlmProviderRequest | null | undefined,
  userPrompt: string,
  options: CallLlmOptions,
): Promise<string | ModelResponse> {
  const sameEndpoint =
    fallback &&
    fallback.apiType === primary.apiType &&
    normalizeBaseUrl(fallback.baseUrl) === normalizeBaseUrl(primary.baseUrl) &&
    fallback.apiKey === primary.apiKey &&
    fallback.model === primary.model;
  if (!fallback || sameEndpoint) return callLlm(primary, userPrompt, options as CallLlmOptions & { returnMetadata: true }) as unknown as Promise<string | ModelResponse>;

  try {
    return (await callLlm(primary, userPrompt, options as CallLlmOptions & { returnMetadata: true })) as unknown as string | ModelResponse;
  } catch (error) {
    const transient = Boolean((error as Record<string, unknown>).transient);
    if (!transient) throw error;
    return (await callLlm(fallback, userPrompt, options as CallLlmOptions & { returnMetadata: true })) as unknown as string | ModelResponse;
  }
}

/**
 * 从 settings 解析主/备 LlmProviderRequest。retryModel 为空时不产生 fallback；
 * retryProviderId 为空时复用主 Provider。
 */
export function resolveLlmProviders(settings: AppSettings): { primary: LlmProviderRequest | null; fallback?: LlmProviderRequest } {
  const ai = settings.llmConfig.ai;
  const primaryProvider = settings.llmConfig.providers.find((item) => item.id === ai.providerId);
  if (!ai.enabled || !primaryProvider || !primaryProvider.apiKey.trim() || !primaryProvider.baseUrl.trim() || !ai.model.trim()) {
    return { primary: null };
  }
  const primary: LlmProviderRequest = {
    apiType: primaryProvider.apiType,
    baseUrl: primaryProvider.baseUrl,
    apiKey: primaryProvider.apiKey,
    model: ai.model.trim(),
    timeoutMs: ai.timeoutMs ?? 30_000,
  };
  const retryModel = ai.retryModel?.trim();
  if (!retryModel) return { primary };
  const retryProviderId = ai.retryProviderId?.trim() || ai.providerId;
  const retryProvider = settings.llmConfig.providers.find((item) => item.id === retryProviderId) ?? primaryProvider;
  if (!retryProvider.apiKey.trim() || !retryProvider.baseUrl.trim()) return { primary };
  if (retryProvider.id === primaryProvider.id && retryModel === ai.model.trim()) return { primary };
  const fallback: LlmProviderRequest = {
    apiType: retryProvider.apiType,
    baseUrl: retryProvider.baseUrl,
    apiKey: retryProvider.apiKey,
    model: retryModel,
    timeoutMs: ai.timeoutMs ?? 30_000,
  };
  return { primary, fallback };
}
