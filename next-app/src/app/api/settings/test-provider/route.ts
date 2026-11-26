import { NextRequest } from "next/server";
import { errorMessage } from "@/lib/format";
import { ApiError, fail, internalError, ok } from "@/lib/api";
import { requiresSsrfGuard } from "@/lib/security";
import { assertPublicSafeUrl } from "@/lib/ssrf-guard";
import { SECOND_MS } from "@/lib/time";
import { z } from "zod";

export const dynamic = "force-dynamic";

const testSchema = z.object({
  apiType: z.enum(["openai", "anthropic"]),
  baseUrl: z.string().min(1),
  apiKey: z.string().min(1),
  model: z.string().min(1),
});

function normalizeBaseUrl(baseUrl: string): string {
  return baseUrl.trim().replace(/\/+$/, "");
}

async function testOpenAi(baseUrl: string, apiKey: string, model: string, guarded: boolean) {
  const endpoint = `${normalizeBaseUrl(baseUrl)}/chat/completions`;
  const response = await fetch(endpoint, {
    method: "POST",
    redirect: guarded ? "error" : "follow",
    signal: AbortSignal.timeout(15 * SECOND_MS),
    headers: { "content-type": "application/json", authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      messages: [{ role: "user", content: "Hi" }],
      max_tokens: 10,
    }),
  });
  const body = await response.json().catch(() => null) as Record<string, unknown> | null;
  if (!response.ok) {
    const message = body && typeof body.error === "object" && body.error
      ? String((body.error as Record<string, unknown>).message ?? "")
      : `HTTP ${response.status}`;
    throw new Error(message || `HTTP ${response.status}`);
  }
  const choices = Array.isArray(body?.choices) ? body.choices as Array<Record<string, unknown>> : [];
  const message = choices[0]?.message as Record<string, unknown> | undefined;
  const content = typeof message?.content === "string" ? message.content : "";
  const usage = body?.usage && typeof body.usage === "object" ? body.usage as Record<string, unknown> : {};
  return {
    model: String(body?.model ?? model),
    responsePreview: content.slice(0, 100) || "(empty content)",
    inputTokens: typeof usage.prompt_tokens === "number" ? usage.prompt_tokens : null,
    outputTokens: typeof usage.completion_tokens === "number" ? usage.completion_tokens : null,
  };
}

async function testAnthropic(baseUrl: string, apiKey: string, model: string, guarded: boolean) {
  const endpoint = `${normalizeBaseUrl(baseUrl)}/messages`;
  const response = await fetch(endpoint, {
    method: "POST",
    redirect: guarded ? "error" : "follow",
    signal: AbortSignal.timeout(15 * SECOND_MS),
    headers: { "content-type": "application/json", "x-api-key": apiKey, "anthropic-version": "2023-06-01" },
    body: JSON.stringify({
      model,
      max_tokens: 10,
      messages: [{ role: "user", content: "Hi" }],
    }),
  });
  const body = await response.json().catch(() => null) as Record<string, unknown> | null;
  if (!response.ok) {
    const message = body && typeof body.error === "object" && body.error
      ? String((body.error as Record<string, unknown>).message ?? "")
      : `HTTP ${response.status}`;
    throw new Error(message || `HTTP ${response.status}`);
  }
  const content = Array.isArray(body?.content) ? body.content as Array<Record<string, unknown>> : [];
  const text = content.map((item) => item.type === "text" ? String(item.text ?? "") : "").join("");
  const usage = body?.usage && typeof body.usage === "object" ? body.usage as Record<string, unknown> : {};
  return {
    model: String(body?.model ?? model),
    responsePreview: text.slice(0, 100) || "(empty content)",
    inputTokens: typeof usage.input_tokens === "number" ? usage.input_tokens : null,
    outputTokens: typeof usage.output_tokens === "number" ? usage.output_tokens : null,
  };
}

export async function POST(request: NextRequest) {
  try {
    const input = testSchema.parse(await request.json());
    const guarded = requiresSsrfGuard(request);
    if (guarded) {
      await assertPublicSafeUrl(normalizeBaseUrl(input.baseUrl));
    }
    const start = Date.now();
    const result = input.apiType === "anthropic"
      ? await testAnthropic(input.baseUrl, input.apiKey, input.model, guarded)
      : await testOpenAi(input.baseUrl, input.apiKey, input.model, guarded);
    return ok({ ...result, durationMs: Date.now() - start });
  } catch (error) {
    if (error instanceof ApiError) return fail(error.code, error.message, error.status);
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "参数无效", 400, error.issues);
    const timeout = error instanceof DOMException && error.name === "TimeoutError";
    if (timeout) return fail("TIMEOUT", "连接超时（15秒）", 504);
    return internalError(error, errorMessage(error, "连接失败"));
  }
}
