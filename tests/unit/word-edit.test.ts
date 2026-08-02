import { afterEach, describe, expect, it, vi } from "vitest";
import { sqlite } from "@/db/client";
import { emptyDictionaryContent } from "@/modules/dictionary/content";
import { applyYoudaoContent, previewYoudaoContent } from "@/modules/words/youdao-refresh";

const now = Date.now();

function insertWord(term: string): number {
  const result = sqlite.prepare(`INSERT INTO words
    (term, normalized_term, source_language, target_language, entry_type, content_type, created_at, updated_at)
    VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'WORD', ?, ?)`)
    .run(term, term.toLowerCase(), now, now);
  return Number(result.lastInsertRowid);
}

function contentWithDefinition(text: string) {
  const content = emptyDictionaryContent();
  content.definitions = [{ language: "zh-CN", partOfSpeech: "n", text, source: "youdao", isUserEdited: false }];
  return content;
}

function youdaoHtml(...lines: string[]): string {
  return `<html><body>${lines.map((line) => `<div>${line}</div>`).join("")}</body></html>`;
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("applyYoudaoContent with newTerm", () => {
  it("updates the word term and normalized term together with the content", () => {
    const wordId = insertWord("hello");
    const detail = applyYoudaoContent(wordId, contentWithDefinition("世界"), "FILL_MISSING_FIELDS", [], "world")!;

    expect(detail.term).toBe("world");
    expect(detail.normalizedTerm).toBe("world");
    expect(detail.initializationStatus).toBe("PARTIAL");
    expect(detail.content.definitions).toEqual([expect.objectContaining({ text: "世界" })]);
    const row = sqlite.prepare("SELECT term, normalized_term FROM words WHERE id = ?").get(wordId) as { term: string; normalized_term: string };
    expect(row.term).toBe("world");
    expect(row.normalized_term).toBe("world");
  });

  it("throws TERM_ALREADY_EXISTS when another word already has the same identity", () => {
    insertWord("hello");
    const targetId = insertWord("there");
    expect(() => applyYoudaoContent(targetId, contentWithDefinition("那里"), "FILL_MISSING_FIELDS", [], "Hello"))
      .toThrow("TERM_ALREADY_EXISTS");
  });

  it("allows keeping the same term as a no-op term change", () => {
    const wordId = insertWord("hello");
    const detail = applyYoudaoContent(wordId, contentWithDefinition("你好"), "FILL_MISSING_FIELDS", [], "  hello ")!;
    expect(detail.term).toBe("hello");
    const row = sqlite.prepare("SELECT term FROM words WHERE id = ?").get(wordId) as { term: string };
    expect(row.term).toBe("hello");
  });

  it("throws TERM_REQUIRED for a blank new term", () => {
    const wordId = insertWord("hello");
    expect(() => applyYoudaoContent(wordId, contentWithDefinition("你好"), "FILL_MISSING_FIELDS", [], "   "))
      .toThrow("TERM_REQUIRED");
  });

  it("leaves the term unchanged when newTerm is omitted", () => {
    const wordId = insertWord("hello");
    applyYoudaoContent(wordId, contentWithDefinition("你好"), "FILL_MISSING_FIELDS", []);
    const row = sqlite.prepare("SELECT term FROM words WHERE id = ?").get(wordId) as { term: string };
    expect(row.term).toBe("hello");
  });
});

describe("previewYoudaoContent termOverride", () => {
  it("fetches Youdao content for the overridden term", async () => {
    const wordId = insertWord("hello");
    const fetchMock = vi.fn().mockResolvedValue(new Response(
      youdaoHtml("world", "英 [wɜːld]", "美 [wɝːld]", "简明", "n. 世界"),
      { status: 200 },
    ));
    vi.stubGlobal("fetch", fetchMock);

    const result = await previewYoudaoContent(wordId, "world");

    expect(String(fetchMock.mock.calls[0]?.[0])).toContain("dict.youdao.com/w/eng/world");
    expect(result.hasContent).toBe(true);
    expect(result.content.definitions).toEqual([expect.objectContaining({ text: "世界" })]);
  });

  it("fetches the stored term when no override is provided", async () => {
    const wordId = insertWord("hello");
    const fetchMock = vi.fn().mockResolvedValue(new Response(
      youdaoHtml("hello", "英 [həˈləʊ]", "美 [həˈloʊ]", "简明", "int. 你好"),
      { status: 200 },
    ));
    vi.stubGlobal("fetch", fetchMock);

    const result = await previewYoudaoContent(wordId);

    expect(String(fetchMock.mock.calls[0]?.[0])).toContain("dict.youdao.com/w/eng/hello");
    expect(result.hasContent).toBe(true);
  });
});
