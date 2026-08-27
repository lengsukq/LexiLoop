import { afterEach, describe, expect, it, vi } from "vitest";
import { DEFAULT_SETTINGS } from "@/lib/config";
import type { AppSettings } from "@/lib/types";
import { lookupDictionary } from "@/modules/dictionary/pipeline";
import { settingsForAiAttempt } from "@/modules/settings/service";

afterEach(() => {
  vi.unstubAllGlobals();
});

function settingsWithAiEnabled(): AppSettings {
  return {
    ...DEFAULT_SETTINGS,
    dictionaryApiEnabled: false,
    myMemoryEnabled: false,
    youdaoEnabled: false,
    llmConfig: {
      providers: [
        { id: "openai", name: "OpenAI", apiType: "openai", apiKey: "", baseUrl: "https://api.openai.com/v1" },
      ],
      ai: {
        ...DEFAULT_SETTINGS.llmConfig.ai,
        enabled: true,
        providerId: "openai",
        model: "gpt-4o-mini",
      },
    },
  };
}

describe("AI lexical pipeline", () => {
  it("switches to the configured fallback model from the second task attempt", () => {
    const settings = settingsWithAiEnabled();
    settings.llmConfig.providers.push({ id: "fallback", name: "Fallback", apiType: "openai", apiKey: "", baseUrl: "https://fallback.test/v1" });
    settings.llmConfig.ai.retryProviderId = "fallback";
    settings.llmConfig.ai.retryModel = "fallback-model";

    expect(settingsForAiAttempt(settings, 1).llmConfig.ai.model).toBe("gpt-4o-mini");
    expect(settingsForAiAttempt(settings, 2).llmConfig.ai.model).toBe("fallback-model");
    expect(settingsForAiAttempt(settings, 2).llmConfig.ai.providerId).toBe("fallback");
  });

  it("can switch to fallback via retryModel only", () => {
    const settings = settingsWithAiEnabled();
    settings.llmConfig.ai.retryModel = "gpt-4.1-mini";

    expect(settingsForAiAttempt(settings, 1).llmConfig.ai.model).toBe("gpt-4o-mini");
    expect(settingsForAiAttempt(settings, 2).llmConfig.ai.model).toBe("gpt-4.1-mini");
  });

  it("falls back to AI only when no dictionary provider returns definitions", async () => {
    const settings = settingsWithAiEnabled();
    settings.translationProviderOrder = ["ai"];
    const result = await lookupDictionary({
      term: "happy",
      normalizedTerm: "happy",
      entryType: "WORD",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
    }, settings);

    expect(result.attempts.map((attempt) => attempt.providerId)).toEqual(["ai:openai:gpt-4o-mini"]);
    expect(result.attempts[0]?.errorCode).toBe("AI_CONFIG_INCOMPLETE");
  });

  it("uses Youdao as the default fact source even when AI supplementation is enabled", async () => {
    const settings = settingsWithAiEnabled();
    settings.youdaoEnabled = true;
    settings.translationProviderOrder = ["youdao"];
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("<html><body><div>简明</div><div>int. 你好</div></body></html>", { status: 200 })));

    const result = await lookupDictionary({
      term: "hello",
      normalizedTerm: "hello",
      entryType: "WORD",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
    }, settings);

    expect(result.attempts.map((attempt) => attempt.providerId)).toEqual(["youdao"]);
    expect(result.content.definitions[0]).toEqual(expect.objectContaining({ source: "youdao", text: "你好" }));
  });

  it("keeps an explicit Youdao selection strict when the dictionary returns no content", async () => {
    const settings = settingsWithAiEnabled();
    settings.youdaoEnabled = true;
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("<html><body>没有匹配结果</body></html>", { status: 200 })));

    const result = await lookupDictionary({
      term: "not-a-word",
      normalizedTerm: "not-a-word",
      entryType: "WORD",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
      requestedFields: ["definitions"],
      requestedProviders: ["youdao"],
      providerStrategy: "PRIORITY_FALLBACK",
    }, settings);

    expect(result.content.definitions).toHaveLength(0);
    expect(result.attempts).toHaveLength(1);
    expect(result.attempts[0]?.providerId).toBe("youdao");
    expect(result.attempts[0]?.status).toBe("FAILED");
  });

  it("falls back from Youdao primary endpoint to its official result endpoint", async () => {
    const settings = settingsWithAiEnabled();
    settings.youdaoEnabled = true;
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(new Response("", { status: 503 }))
      .mockResolvedValueOnce(new Response("<html><body><div>简明</div><div>int. 你好</div></body></html>", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const result = await lookupDictionary({
      term: "hello",
      normalizedTerm: "hello",
      entryType: "WORD",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
      requestedProviders: ["youdao"],
      providerStrategy: "PRIORITY_FALLBACK",
    }, settings);

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(result.content.definitions[0]).toEqual(expect.objectContaining({ source: "youdao", text: "你好" }));
    expect(result.attempts[0]?.metadata?.endpointAttempts).toHaveLength(2);
  });
});
