import { NextRequest } from "next/server";
import { z } from "zod";
import { handleRouteError } from "@/lib/api";
import { requiresSsrfGuard } from "@/lib/security";
import { assertPublicSafeUrl } from "@/lib/ssrf-guard";
import { SECOND_MS } from "@/lib/time";
import { normalizeBaseUrl } from "@/lib/url";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

const schema = z.object({
  apiType: z.enum(["openai", "anthropic"]),
  baseUrl: z.string().min(1).max(1000),
  apiKey: z.string().min(1).max(1000),
  timeoutMs: z.number().int().min(1000).max(55 * SECOND_MS).default(30 * SECOND_MS),
  payload: z.record(z.string(), z.unknown()),
}).strict();

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    const baseUrl = normalizeBaseUrl(input.baseUrl);
    if (requiresSsrfGuard(request)) {
      await assertPublicSafeUrl(baseUrl);
    }

    const endpoint = input.apiType === "anthropic"
      ? `${baseUrl}/messages`
      : `${baseUrl}/chat/completions`;
    const headers: Record<string, string> = input.apiType === "anthropic"
      ? {
          "content-type": "application/json",
          "x-api-key": input.apiKey,
          "anthropic-version": "2023-06-01",
        }
      : {
          "content-type": "application/json",
          authorization: `Bearer ${input.apiKey}`,
        };

    const upstream = await fetch(endpoint, {
      method: "POST",
      redirect: "error",
      signal: AbortSignal.timeout(input.timeoutMs),
      headers,
      body: JSON.stringify(input.payload),
    });

    const raw = await upstream.text();
    return new Response(raw, {
      status: upstream.status,
      headers: {
        "Content-Type": upstream.headers.get("content-type") ?? "application/json; charset=utf-8",
        "Cache-Control": "no-store",
      },
    });
  } catch (error) {
    return handleRouteError(error, {
      validationMessage: "AI 代理参数无效。",
      fallbackMessage: "AI 代理请求失败。",
    });
  }
}
