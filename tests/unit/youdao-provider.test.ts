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
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("unavailable", { status: 503 }))
      .mockResolvedValueOnce(new Response(html("英 [həˈləʊ]", "美 [həˈloʊ]", "int. 你好"), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await new YoudaoProvider().lookup({
      ...baseInput,
      requestedFields: ["definitions", "pronunciations.phonetic"],
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[0]?.[0])).toContain("dict.youdao.com/w/eng/hello");
    expect(String(fetchMock.mock.calls[1]?.[0])).toContain("www.youdao.com/result");
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
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(html("英 [həˈləʊ]"), { status: 200 }))
      .mockResolvedValueOnce(new Response(html("int. 你好"), { status: 200 }));
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
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response(html("n. 问候；招呼"), { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await new YoudaoProvider().lookup({
      ...baseInput,
      requestedFields: ["definitions"],
    });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(result.content?.definitions).toHaveLength(1);
    expect(result.metadata?.sourceEndpoint).toBe("dict.youdao.com");
    expect(result.metadata?.fallbackUsed).toBe(false);
  });

  it("returns a combined transient failure after both endpoints fail", async () => {
    const timeout = new Error("request timed out");
    timeout.name = "TimeoutError";
    const fetchMock = vi.fn()
      .mockRejectedValueOnce(timeout)
      .mockResolvedValueOnce(new Response("bad gateway", { status: 502 }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await new YoudaoProvider().lookup(baseInput);

    expect(fetchMock).toHaveBeenCalledTimes(2);
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
});
