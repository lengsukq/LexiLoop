import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { sqlite } from "@/db/client";
import type { DictionaryContent } from "@/lib/types";

const { lookupMock } = vi.hoisted(() => ({ lookupMock: vi.fn() }));

vi.mock("@/modules/dictionary/pipeline", () => ({
  lookupDictionary: (...args: unknown[]) => lookupMock(...args),
}));

import { createManualPreview } from "@/modules/manual/service";

const emptyContent: DictionaryContent = {
  definitions: [],
  pronunciations: [],
  examples: [],
  phrases: [],
  forms: [],
  synonyms: [],
  antonyms: [],
  wordFamily: [],
  confusedWords: [],
  roots: [],
  affixes: [],
  tags: [],
  summary: { shortDefinition: null, translation: null, cefrLevel: null, frequency: null },
  learning: { pronunciationTip: null, mnemonic: null, commonMistakes: [] },
  sentenceAnalysis: {
    grammarPattern: null,
    grammarExplanation: null,
    grammarNotes: [],
    keyExpressions: [],
    similarExamples: [],
    variations: [],
  },
};

function result(content: typeof emptyContent, attempts: unknown[]) {
  return {
    content,
    attempts,
    hasTransientFailure: false,
    contentSource: "DICTIONARY_ONLY",
    requiredProviderFailure: null,
  };
}

describe("manual preview youdao fallback", () => {
  beforeEach(() => {
    lookupMock.mockReset();
  });
  afterEach(async () => {
    await sqlite.prepare("DELETE FROM manual_previews").run();
  });

  it("falls back to tencent-translate and ai when youdao returns nothing", async () => {
    const filled = {
      ...emptyContent,
      definitions: [{ language: "zh-CN", partOfSpeech: null, text: "照顾", source: "tencent-translate", isUserEdited: false }],
    };
    lookupMock
      .mockResolvedValueOnce(result(emptyContent, [{
        providerId: "youdao", status: "EMPTY", durationMs: 1, fieldsReturned: [], errorCode: "EMPTY_RESULT", errorMessage: "",
      }]))
      .mockResolvedValueOnce(result(filled, [{
        providerId: "tencent-translate", status: "SUCCESS", durationMs: 1, fieldsReturned: ["definitions"], errorCode: null, errorMessage: null,
      }]));

    const preview = await createManualPreview({
      text: "take care of", sourceLanguage: "en", targetLanguage: "zh-CN", contentType: "PHRASE",
    });

    expect(lookupMock).toHaveBeenCalledTimes(2);
    expect(lookupMock.mock.calls[0]?.[0].requestedProviders).toEqual(["youdao"]);
    expect(lookupMock.mock.calls[1]?.[0].requestedProviders).toEqual(["tencent-translate", "ai"]);
    expect(preview.providerAttempts.map((a) => a.providerId)).toEqual(["youdao", "tencent-translate"]);
    expect(preview.content.definitions[0]?.text).toBe("照顾");
    expect(preview.contentType).toBe("PHRASE");
  });

  it("keeps the youdao result when it succeeds and never queries fallbacks", async () => {
    const filled = {
      ...emptyContent,
      definitions: [{ language: "zh-CN", partOfSpeech: null, text: "宣传册", source: "youdao", isUserEdited: false }],
    };
    lookupMock.mockResolvedValueOnce(result(filled, [{
      providerId: "youdao", status: "SUCCESS", durationMs: 1, fieldsReturned: ["definitions"], errorCode: null, errorMessage: null,
    }]));

    const preview = await createManualPreview({
      text: "BROCHURE", sourceLanguage: "en", targetLanguage: "zh-CN", contentType: "WORD",
    });

    expect(lookupMock).toHaveBeenCalledTimes(1);
    expect(preview.providerAttempts.map((a) => a.providerId)).toEqual(["youdao"]);
    expect(preview.content.definitions[0]?.text).toBe("宣传册");
  });

  it("throws the original error when both youdao and fallbacks return nothing", async () => {
    lookupMock.mockResolvedValue(result(emptyContent, []));

    await expect(createManualPreview({
      text: "zzz", sourceLanguage: "en", targetLanguage: "zh-CN", contentType: "WORD",
    })).rejects.toThrow("词典没有返回可用释义");
    expect(lookupMock).toHaveBeenCalledTimes(2);
  });
});
