import { NextRequest } from "next/server";
import { errorMessage } from "@/lib/format";
import { ApiError, fail, internalError, ok } from "@/lib/api";
import { requiresSsrfGuard } from "@/lib/security";
import { assertPublicSafeUrl } from "@/lib/ssrf-guard";
import { formatAiProviderError } from "@/modules/ai-tasks/provider-error";
import { SECOND_MS } from "@/lib/time";
import { z } from "zod";

export const dynamic = "force-dynamic";

const inputSchema = z.object({
  apiType: z.enum(["openai", "anthropic"]),
  baseUrl: z.string().min(1),
  apiKey: z.string().min(1),
});

function normalizeBaseUrl(baseUrl: string): string {
  return baseUrl.trim().replace(/\/+$/, "");
}

function modelsFromPayload(payload: unknown): string[] {
  const body = payload && typeof payload === "object" ? payload as Record<string, unknown> : null;
  const candidates = Array.isArray(payload)
    ? payload
    : Array.isArray(body?.data)
      ? body.data
      : Array.isArray(body?.models)
        ? body.models
        : [];
  return [...new Set(candidates.map((item) => {
    if (typeof item === "string") return item.trim();
    if (!item || typeof item !== "object") return "";
    const record = item as Record<string, unknown>;
    return String(record.id ?? record.model ?? record.name ?? "").trim();
  }).filter(Boolean))].sort((left, right) => left.localeCompare(right)).slice(0, 1000);
}

export async function POST(request: NextRequest) {
  try {
    const input = inputSchema.parse(await request.json());
    const baseUrl = normalizeBaseUrl(input.baseUrl);
    if (requiresSsrfGuard(request)) {
      await assertPublicSafeUrl(baseUrl);
    }
    const response = await fetch(`${baseUrl}/models`, {
      redirect: "error",
      signal: AbortSignal.timeout(15 * SECOND_MS),
      headers: input.apiType === "anthropic"
        ? { "x-api-key": input.apiKey, "anthropic-version": "2023-06-01" }
        : { authorization: `Bearer ${input.apiKey}` },
    });
    const raw = await response.text().catch(() => "");
    let body: unknown = null;
    try { body = JSON.parse(raw); } catch { /* handled below */ }
    if (!response.ok) {
      const providerError = body && typeof body === "object" && "error" in body
        ? (body as { error?: unknown }).error
        : null;
      const error = providerError && typeof providerError === "object"
        ? String(((providerError as Record<string, unknown>).message ?? ""))
        : formatAiProviderError(response.status, raw);
      return fail("PROVIDER_MODELS_FAILED", error || `Models 接口请求失败（${response.status}）。`, response.status >= 500 ? 502 : 400);
    }
    const models = modelsFromPayload(body);
    if (!models.length) return fail("MODELS_EMPTY", "Models 接口没有返回可识别的模型列表。", 422);
    return ok({ models });
  } catch (error) {
    if (error instanceof ApiError) return fail(error.code, error.message, error.status);
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "Provider 配置不完整，无法读取模型。", 400, error.issues);
    const timeout = error instanceof DOMException && error.name === "TimeoutError";
    if (timeout) return fail("TIMEOUT", "Models 接口连接超时（15秒）。", 504);
    return internalError(error, errorMessage(error, "读取模型失败。"));
  }
}
