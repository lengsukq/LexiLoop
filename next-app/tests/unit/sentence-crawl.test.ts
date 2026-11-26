import { afterEach, describe, expect, it, vi } from "vitest";
import { sqlite } from "@/db/client";
import { DEFAULT_SETTINGS } from "@/lib/config";
import type { AppSettings } from "@/lib/types";
import { contentStatus } from "@/modules/dictionary/content";
import { lookupDictionary } from "@/modules/dictionary/pipeline";
import { startStudySession } from "@/modules/study/service";

afterEach(() => {
  vi.unstubAllGlobals();
});

function html(...lines: string[]): string {
  return `<html><body>${lines.map((line) => `<div>${line}</div>`).join("")}</body></html>`;
}

function sentenceSettings(): AppSettings {
  return {
    ...DEFAULT_SETTINGS,
    dictionaryApiEnabled: false,
    myMemoryEnabled: false,
    merriamWebsterEnabled: false,
    tencentTranslateEnabled: true,
    tencentTranslateSecretId: "test-id",
    tencentTranslateSecretKey: "test-key",
    translationProviderOrder: ["youdao"],
  };
}

async function insertSentence(term: string, definitions: unknown[], translation: string | null): Promise<number> {
  const now = Date.now();
  const result = await sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, content_type,
     initialization_status, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'PHRASE', 'SENTENCE', 'READY', ?, ?)`)
    .run(term, term.toLocaleLowerCase(), now, now);
  const wordId = Number(result.lastInsertRowid);
  await sqlite.prepare(`INSERT INTO word_contents (word_id, definitions_json, summary_json, updated_at)
    VALUES (?, ?, ?, ?)`)
    .run(
      wordId,
      JSON.stringify(definitions),
      JSON.stringify({ shortDefinition: null, translation, cefrLevel: null, frequency: null }),
      now,
    );
  return wordId;
}

describe("sentence crawling", () => {
  it("extracts the Youdao machine translation as the sentence meaning", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response(html("有道翻译", "I am tired", "我累了", "以上为机器翻译"), { status: 200 })));

    const result = await lookupDictionary({
      term: "I am tired",
      normalizedTerm: "i am tired",
      entryType: "SENTENCE",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
    }, sentenceSettings());

    expect(result.attempts.map((attempt) => attempt.providerId)).toEqual(["youdao"]);
    expect(result.content.definitions).toEqual([
      expect.objectContaining({ language: "zh-CN", text: "我累了", source: "youdao:translation" }),
    ]);
    expect(result.content.summary.translation).toBe("我累了");
    expect(contentStatus(result.content, "SENTENCE")).toBe("READY");
  });

  it("falls back to Tencent translation when Youdao returns no meaning for a sentence", async () => {
    const fetchMock = vi.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("youdao.com")) return new Response(html("双语例句", "1", "How are you?", "你好吗？"), { status: 200 });
      if (url.includes("tmt.tencentcloudapi.com") || url.includes("tencent")) {
        return new Response(JSON.stringify({ Response: { TargetText: "你好吗？" } }), { status: 200 });
      }
      return new Response(JSON.stringify({ Response: { TargetText: "你好吗？" } }), { status: 200 });
    });
    vi.stubGlobal("fetch", fetchMock);

    const result = await lookupDictionary({
      term: "How are you?",
      normalizedTerm: "how are you?",
      entryType: "SENTENCE",
      sourceLanguage: "en",
      targetLanguage: "zh-CN",
    }, sentenceSettings());

    expect(result.attempts.map((attempt) => attempt.providerId)).toEqual(["youdao", "tencent-translate"]);
    expect(result.content.definitions).toEqual([
      expect.objectContaining({ text: "你好吗？", source: "tencent-translate" }),
    ]);
    expect(contentStatus(result.content, "SENTENCE")).not.toBe("FAILED");
  });

  it("admits sentences with definitions or a summary translation, and skips meaning-less ones", async () => {
    await insertSentence("How are you?", [{ language: "zh-CN", partOfSpeech: null, text: "你好吗？", source: "test", isUserEdited: false }], null);
    await insertSentence("See you later.", [], "回头见");
    await insertSentence("No meaning here.", [], null);

    const session = await startStudySession("SENTENCE_REVIEW", false);

    const terms = session.items.map((item) => item.word.term);
    expect(terms).toContain("How are you?");
    expect(terms).toContain("See you later.");
    expect(terms).not.toContain("No meaning here.");
  });
});
