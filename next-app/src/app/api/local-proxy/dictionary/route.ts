import { NextRequest } from "next/server";
import { z } from "zod";
import { handleRouteError, ok } from "@/lib/api";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 30;

const requestSchema = z.object({
  target: z.enum([
    "youdao-dict",
    "youdao-result",
    "iciba",
    "dictionaryapi",
    "mymemory",
    "merriam-webster",
  ]),
  term: z.string().trim().min(1).max(1200),
  sourceLanguage: z.string().trim().max(40).optional(),
  targetLanguage: z.string().trim().max(40).optional(),
  reference: z.enum(["collegiate", "thesaurus"]).optional(),
  apiKey: z.string().max(300).optional(),
  timeoutMs: z.number().int().min(1000).max(20_000).optional(),
}).strict();

function buildAllowlistedTarget(input: z.infer<typeof requestSchema>): {
  url: URL;
  headers: Record<string, string>;
  timeoutMs: number;
} {
  const term = input.term.trim();
  const timeoutMs = input.timeoutMs ?? 10_000;

  switch (input.target) {
    case "youdao-dict":
      return {
        url: new URL(`https://dict.youdao.com/w/eng/${encodeURIComponent(term)}`),
        headers: {
          accept: "text/html,application/xhtml+xml",
          "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
          "cache-control": "no-cache",
          "user-agent": "Mozilla/5.0 LexiLoop",
        },
        timeoutMs,
      };
    case "youdao-result": {
      const url = new URL("https://www.youdao.com/result");
      url.searchParams.set("word", term);
      url.searchParams.set("lang", "en");
      return {
        url,
        headers: {
          accept: "text/html,application/xhtml+xml",
          "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
          "cache-control": "no-cache",
          "user-agent": "Mozilla/5.0 LexiLoop",
        },
        timeoutMs,
      };
    }
    case "iciba":
      return {
        url: new URL(`https://www.iciba.com/word?w=${encodeURIComponent(term)}`),
        headers: {
          accept: "text/html,application/xhtml+xml",
          "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
          "cache-control": "no-cache",
          "user-agent": "Mozilla/5.0 LexiLoop",
        },
        timeoutMs,
      };
    case "dictionaryapi":
      return {
        url: new URL(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(term)}`),
        headers: { accept: "application/json", "user-agent": "LexiLoop/1.0" },
        timeoutMs,
      };
    case "mymemory": {
      const url = new URL("https://api.mymemory.translated.net/get");
      url.searchParams.set("q", term);
      url.searchParams.set(
        "langpair",
        `${input.sourceLanguage || "en"}|${input.targetLanguage || "zh-CN"}`,
      );
      return {
        url,
        headers: { "user-agent": "LexiLoop/1.0" },
        timeoutMs: Math.min(timeoutMs, 8_000),
      };
    }
    case "merriam-webster": {
      const reference = input.reference ?? "collegiate";
      const key = (input.apiKey ?? "").trim();
      return {
        url: new URL(
          `https://www.dictionaryapi.com/api/v3/references/${reference}/json/${encodeURIComponent(term)}?key=${encodeURIComponent(key)}`,
        ),
        headers: { accept: "application/json", "user-agent": "LexiLoop/1.0" },
        timeoutMs,
      };
    }
  }
}

export async function POST(request: NextRequest) {
  try {
    const input = requestSchema.parse(await request.json());
    const target = buildAllowlistedTarget(input);
    const response = await fetch(target.url, {
      redirect: "follow",
      signal: AbortSignal.timeout(target.timeoutMs),
      headers: target.headers,
    });
    const body = await response.text();
    return ok({
      status: response.status,
      contentType: response.headers.get("content-type") ?? "text/plain; charset=utf-8",
      body,
    });
  } catch (error) {
    return handleRouteError(error, {
      validationMessage: "词典代理参数无效。",
      fallbackMessage: "词典代理请求失败。",
    });
  }
}
