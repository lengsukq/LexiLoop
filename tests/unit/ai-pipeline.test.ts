import { describe, expect, it } from "vitest";
import { DEFAULT_SETTINGS } from "@/lib/config";
import type { AppSettings } from "@/lib/types";
import { lookupDictionary } from "@/modules/dictionary/pipeline";

function settingsWithAiEnabled(): AppSettings {
  return {
    ...DEFAULT_SETTINGS,
    dictionaryApiEnabled: false,
    myMemoryEnabled: false,
    ecdictEnabled: false,
    llmConfig: {
      providers: {
        ...DEFAULT_SETTINGS.llmConfig.providers,
        openai: { apiKey: "", baseUrl: "https://api.openai.com/v1" },
      },
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
  it("requires the AI provider to succeed when AI initialization is enabled", async () => {
    const result = await lookupDictionary({
      term: "happy",
      normalizedTerm: "happy",
      entryType: "WORD",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
    }, settingsWithAiEnabled());

    expect(result.requiredProviderFailure).toEqual({
      transient: false,
      errorCode: "AI_CONFIG_INCOMPLETE",
      errorMessage: "AI 提供商、API Key、接口地址或模型未配置完整",
    });
    expect(result.attempts[0]?.providerId).toContain("ai:openai");
    expect(result.attempts[0]?.status).toBe("FAILED");
  });
});
