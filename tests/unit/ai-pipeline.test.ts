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
    ecdictEnabled: false,
    youdaoEnabled: false,
    llmConfig: {
      providers: [
        { id: "openai", name: "OpenAI", apiType: "openai", apiKey: "", baseUrl: "https://api.openai.com/v1" },
      ],
      purposes: {
        ...DEFAULT_SETTINGS.llmConfig.purposes,
        IMPORT_ENRICHMENT: {
          ...DEFAULT_SETTINGS.llmConfig.purposes.IMPORT_ENRICHMENT,
          enabled: true,
          providerId: "openai",
          model: "gpt-4o-mini",
        },
      },
    },
  };
}

describe("AI lexical pipeline", () => {
  it("switches to the configured fallback model from the second task attempt", () => {
    const settings = settingsWithAiEnabled();
    settings.llmConfig.providers.push({ id: "fallback", name: "Fallback", apiType: "openai", apiKey: "", baseUrl: "https://fallback.test/v1" });
    settings.llmConfig.purposes.IMPORT_ENRICHMENT.retryProviderId = "fallback";
    settings.llmConfig.purposes.IMPORT_ENRICHMENT.retryModel = "fallback-model";

    expect(settingsForAiAttempt(settings, 1).llmConfig.purposes.IMPORT_ENRICHMENT.model).toBe("gpt-4o-mini");
    expect(settingsForAiAttempt(settings, 2).llmConfig.purposes.IMPORT_ENRICHMENT.model).toBe("fallback-model");
    expect(settingsForAiAttempt(settings, 2).llmConfig.purposes.IMPORT_ENRICHMENT.providerId).toBe("fallback");
  });

  it("falls back to AI only when no dictionary provider returns definitions", async () => {
    const result = await lookupDictionary({
      term: "happy",
      normalizedTerm: "happy",
      entryType: "WORD",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
    }, settingsWithAiEnabled());

    expect(result.requiredProviderFailure).toBeNull();
    // 所有词典来源禁用 → 无释义 → 降级尝试 AI（配置不完整时安全失败）
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
    expect(result.requiredProviderFailure).toBeNull();
  });
});
