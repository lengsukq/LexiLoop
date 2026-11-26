import { afterEach, describe, expect, it, vi } from "vitest";
import type { LookupInput } from "@/lib/types";
import { YoudaoProvider } from "@/modules/dictionary/providers/youdao";
import { parseYoudaoHtml } from "@/modules/dictionary/providers/youdao-parser";

const baseInput: LookupInput = {
  term: "hello",
  normalizedTerm: "hello",
  entryType: "WORD",
  sourceLanguage: "en",
  targetLanguage: "zh-CN",
};

function html(...lines: string[]): string {
  return `<html><body>${lines.map((line) => `<div>${line}</div>`).join("")}</body></html>`;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("YoudaoProvider fallback", () => {
  it("falls back to youdao.com/result when dict.youdao.com returns an HTTP error", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("dict.youdao.com")) return new Response("unavailable", { status: 503 });
      return new Response(html("英 [həˈləʊ]", "美 [həˈloʊ]", "int. 你好"), { status: 200 });
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await new YoudaoProvider().lookup({
      ...baseInput,
      requestedFields: ["definitions", "pronunciations.phonetic"],
    });

    expect(fetchMock.mock.calls.length).toBeGreaterThanOrEqual(2);
    expect(fetchMock.mock.calls.some((call) => String(call[0]).includes("dict.youdao.com/w/eng/hello"))).toBe(true);
    expect(fetchMock.mock.calls.some((call) => String(call[0]).includes("www.youdao.com/result"))).toBe(true);
    expect(result.content?.definitions).toEqual([
      expect.objectContaining({ language: "zh-CN", partOfSpeech: "int", text: "你好" }),
    ]);
    expect(result.content?.pronunciations).toHaveLength(2);
    expect(result.metadata).toEqual(expect.objectContaining({
      sourceEndpoint: "youdao.com/result",
      fallbackUsed: true,
      endpointAttempts: [
        expect.objectContaining({ endpoint: "dict.youdao.com", status: "FAILED", statusCode: 503 }),
        expect.objectContaining({ endpoint: "youdao.com/result", status: "SUCCESS", statusCode: 200 }),
      ],
    }));
  });

  it("merges partial primary content with fallback content when requested fields are missing", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("dict.youdao.com")) return new Response(html("英 [həˈləʊ]"), { status: 200 });
      return new Response(html("int. 你好"), { status: 200 });
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await new YoudaoProvider().lookup({
      ...baseInput,
      requestedFields: ["definitions", "pronunciations.phonetic"],
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(result.content?.pronunciations).toHaveLength(1);
    expect(result.content?.definitions).toHaveLength(1);
    expect(result.metadata?.fallbackUsed).toBe(true);
  });

  it("does not call the fallback endpoint when the primary endpoint satisfies the requested fields", async () => {
    // Youdao now races both endpoints in parallel and picks the best merged result
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(html("n. 问候；招呼"), { status: 200 }))
      .mockResolvedValueOnce(new Response(html("n. 问候；招呼"), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await new YoudaoProvider().lookup({
      ...baseInput,
      requestedFields: ["definitions"],
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(result.content?.definitions).toHaveLength(1);
    expect(["dict.youdao.com", "youdao.com/result"]).toContain(result.metadata?.sourceEndpoint);
    expect(result.metadata?.endpointAttempts.length).toBeGreaterThanOrEqual(2);
  });

  it("returns a combined transient failure after both endpoints fail", async () => {
    const timeout = new Error("request timed out");
    timeout.name = "TimeoutError";
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("dict.youdao.com")) throw timeout;
      return new Response("bad gateway", { status: 502 });
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await new YoudaoProvider().lookup(baseInput);

    expect(fetchMock.mock.calls.length).toBeGreaterThanOrEqual(2);
    expect(result.content).toBeNull();
    expect(result.errorCode).toBe("ALL_ENDPOINTS_FAILED");
    expect(result.transient).toBe(true);
    expect(result.errorMessage).toContain("dict.youdao.com: TIMEOUT");
    expect(result.errorMessage).toContain("youdao.com/result: HTTP_502");
  });

  it("only supports English word entries", () => {
    const provider = new YoudaoProvider();
    expect(provider.supports(baseInput)).toBe(true);
    expect(provider.supports({ ...baseInput, sourceLanguage: "nl" })).toBe(false);
    expect(provider.supports({ ...baseInput, entryType: "PHRASE" })).toBe(true);
    expect(provider.supports({ ...baseInput, entryType: "SENTENCE" })).toBe(true);
  });

  it("parses dictionary sections, separated word forms, phrases, and source labels", () => {
    const result = parseYoudaoHtml(html(
      "hello", "英 [həˈləʊ]", "美 [həˈloʊ]", "简明", "int. 你好", "n. 招呼，问候",
      "复数", "hellos", "网络释义", "1", "hello", "您好", "短语", "1", "Hello Kitty", "凯蒂猫",
      "双语例句", "1", "Hello, Paul, they chorused.", "你好，保罗。",
    ), { term: "hello", entryType: "WORD", targetLanguage: "zh-CN" });

    expect(result?.definitions).toEqual([
      expect.objectContaining({ language: "zh-CN", partOfSpeech: "int", text: "你好", source: "youdao" }),
      expect.objectContaining({ language: "zh-CN", partOfSpeech: "n", text: "招呼，问候" }),
    ]);
    expect(result?.pronunciations).toEqual([
      expect.objectContaining({ accent: "UK", phonetic: "həˈləʊ", audioUrl: "https://dict.youdao.com/dictvoice?audio=hello&type=1", source: "youdao" }),
      expect.objectContaining({ accent: "US", phonetic: "həˈloʊ", audioUrl: "https://dict.youdao.com/dictvoice?audio=hello&type=2", source: "youdao" }),
    ]);
    expect(result?.forms).toEqual([expect.objectContaining({ type: "PLURAL", value: "hellos" })]);
    expect(result?.phrases).toEqual(expect.arrayContaining([
      expect.objectContaining({ phrase: "Hello Kitty", translation: "凯蒂猫", source: "youdao:phrase" }),
    ]));
    expect(result?.examples).toEqual([
      expect.objectContaining({ sentence: "Hello, Paul, they chorused.", translation: "你好，保罗。", source: "youdao:example" }),
    ]);
  });

  it("uses the direct Youdao translation for phrases and sentences", () => {
    const phrase = parseYoudaoHtml(html("有道翻译", "to take care of", "照顾", "以上为机器翻译"), {
      term: "to take care of", entryType: "PHRASE", targetLanguage: "zh-CN",
    });
    const sentence = parseYoudaoHtml(html("有道翻译", "I am tired", "我累了", "以上为机器翻译"), {
      term: "I am tired", entryType: "SENTENCE", targetLanguage: "zh-CN",
    });

    expect(phrase?.summary?.translation).toBe("照顾");
    expect(phrase?.phrases).toEqual(expect.arrayContaining([
      expect.objectContaining({ phrase: "to take care of", translation: "照顾", source: "youdao:translation" }),
    ]));
    expect(sentence?.summary?.translation).toBe("我累了");
    expect(sentence?.examples?.[0]).toEqual(expect.objectContaining({ sentence: "I am tired", translation: "我累了" }));
  });

  it("falls back to the network definition for phrases without a translation block", () => {
    const inline = parseYoudaoHtml(html("网络释义", "The proportion of …的比例", "双语例句"), {
      term: "The proportion of", entryType: "PHRASE", targetLanguage: "zh-CN",
    });
    const separate = parseYoudaoHtml(html("网络释义", "The proportion of", "…的比例", "双语例句"), {
      term: "The proportion of", entryType: "PHRASE", targetLanguage: "zh-CN",
    });

    expect(inline?.definitions).toEqual([
      expect.objectContaining({ language: "zh-CN", partOfSpeech: null, text: "…的比例", source: "youdao:network", isUserEdited: false }),
    ]);
    expect(separate?.definitions).toEqual([
      expect.objectContaining({ language: "zh-CN", partOfSpeech: null, text: "…的比例", source: "youdao:network", isUserEdited: false }),
    ]);
  });

  it("prefers the direct translation over the network definition for phrases", () => {
    const result = parseYoudaoHtml(html("有道翻译", "The proportion of", "…的比例", "以上为机器翻译", "网络释义", "The proportion of 比例"), {
      term: "The proportion of", entryType: "PHRASE", targetLanguage: "zh-CN",
    });

    expect(result?.definitions).toEqual([
      expect.objectContaining({ text: "…的比例", source: "youdao:translation" }),
    ]);
  });

  it("keeps sentences without a translation block free of invented definitions", () => {
    const result = parseYoudaoHtml(html("双语例句", "1", "How are you?", "你好吗？"), {
      term: "How are you?", entryType: "SENTENCE", targetLanguage: "zh-CN",
    });

    expect(result?.definitions ?? []).toHaveLength(0);
    expect(result?.summary).toBeUndefined();
  });
});
