import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError } from "@/lib/api";
import { callLlm, callLlmWithFallback, type LlmProviderRequest } from "@/modules/llm/client";

const primary: LlmProviderRequest = { apiType: "openai", baseUrl: "https://primary.test", apiKey: "k", model: "m", timeoutMs: 5000 };
const fallback: LlmProviderRequest = { apiType: "openai", baseUrl: "https://fallback.test", apiKey: "k2", model: "m2", timeoutMs: 5000 };

function jsonBody(content: unknown, finish = "stop"): Response {
  return new Response(
    JSON.stringify({ choices: [{ message: { content }, finish_reason: finish }], usage: {} }),
    { status: 200, headers: { "content-type": "application/json" } },
  );
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("callLlm structured output", () => {
  it("空内容时降级到下一档而不是返回空串", async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonBody(""))
      .mockResolvedValueOnce(jsonBody('{"words":[],"phrases":[],"sentences":[]}'));
    vi.stubGlobal("fetch", fetchMock);
    const text = await callLlm(primary, "hi", {
      systemPrompt: "sys",
      jsonSchema: { type: "object" },
    });
    expect(text).toBe('{"words":[],"phrases":[],"sentences":[]}');
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("三档全空时抛 AI_EMPTY_RESPONSE 且可重试", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => jsonBody("")));
    const error = await callLlm(primary, "hi", { systemPrompt: "sys", jsonSchema: { type: "object" } }).catch((e) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as ApiError).code).toBe("AI_EMPTY_RESPONSE");
    expect((error as Record<string, unknown>).transient).toBe(true);
  });

  it("空返回会触发主备切换", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_url: unknown, init: { body?: BodyInit }) => {
        const body = JSON.parse(String(init.body)) as { model: string };
        if (body.model === "m") return jsonBody("");
        return jsonBody('{"words":[],"phrases":[],"sentences":[]}');
      }),
    );
    const text = await callLlmWithFallback(primary, fallback, "hi", {
      systemPrompt: "sys",
      jsonSchema: { type: "object" },
    });
    expect(text).toBe('{"words":[],"phrases":[],"sentences":[]}');
  });

  it("200 + HTML 页面时报 baseUrl 配置错误且不可重试", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("<!doctype html><html><title>AxonHub</title>", { status: 200 })));
    const error = await callLlm(primary, "hi", { systemPrompt: "sys" }).catch((e) => e);
    expect(error).toBeInstanceOf(ApiError);
    expect((error as Error).message).toContain("https://primary.test");
    expect((error as Record<string, unknown>).transient).toBe(false);
  });

  it("模型拒答时直接说明原因", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ choices: [{ message: { content: "", refusal: "policy" }, finish_reason: "stop" }] }), { status: 200 }),
      ),
    );
    const error = await callLlm(primary, "hi", { systemPrompt: "sys" }).catch((e) => e);
    expect((error as Error).message).toContain("拒绝");
  });

  it("length 截断时提示调大输出上限", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonBody("", "length")));
    const error = await callLlm(primary, "hi", { systemPrompt: "sys" }).catch((e) => e);
    expect((error as Error).message).toContain("截断");
  });

  it("兼容嵌套文本块 { text: { value } }", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonBody([{ text: { value: "hello" } }])));
    await expect(callLlm(primary, "hi", { systemPrompt: "sys" })).resolves.toBe("hello");
  });
});

describe("callLlm anthropic", () => {
  it("解析 content 数组并兼容嵌套文本", async () => {
    const provider: LlmProviderRequest = { ...primary, apiType: "anthropic" };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ content: [{ type: "text", text: { value: "hi" } }], stop_reason: "end_turn" }), { status: 200 }),
      ),
    );
    await expect(callLlm(provider, "hi", { systemPrompt: "sys" })).resolves.toBe("hi");
  });

  it("空内容抛 AI_EMPTY_RESPONSE", async () => {
    const provider: LlmProviderRequest = { ...primary, apiType: "anthropic" };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(new Response(JSON.stringify({ content: [], stop_reason: "end_turn" }), { status: 200 })),
    );
    const error = await callLlm(provider, "hi", { systemPrompt: "sys" }).catch((e) => e);
    expect((error as ApiError).code).toBe("AI_EMPTY_RESPONSE");
  });
});
