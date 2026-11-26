import { afterEach, describe, expect, it, vi } from "vitest";
import { sqlite } from "@/db/client";
import { emptyDictionaryContent } from "@/modules/dictionary/content";
import { updateSettings } from "@/modules/settings/service";
import { applyYoudaoContent, previewYoudaoContent } from "@/modules/words/youdao-refresh";

const now = Date.now();

async function insertWord(term: string): Promise<number> {
  const result = await sqlite.prepare(`INSERT INTO words
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
  it("updates the word term and normalized term together with the content", async () => {
    const wordId = await insertWord("hello");
    const detail = (await applyYoudaoContent(wordId, contentWithDefinition("世界"), "FILL_MISSING_FIELDS", [], "world"))!;

    expect(detail.term).toBe("world");
    expect(detail.normalizedTerm).toBe("world");
    expect(detail.initializationStatus).toBe("PARTIAL");
    expect(detail.content.definitions).toEqual([expect.objectContaining({ text: "世界" })]);
    const row = await sqlite.prepare("SELECT term, normalized_term FROM words WHERE id = ?").get(wordId) as { term: string; normalized_term: string };
    expect(row.term).toBe("world");
    expect(row.normalized_term).toBe("world");
  });

  it("throws TERM_ALREADY_EXISTS when another word already has the same identity", async () => {
    await insertWord("hello");
    const targetId = await insertWord("there");
    await expect(applyYoudaoContent(targetId, contentWithDefinition("那里"), "FILL_MISSING_FIELDS", [], "Hello"))
      .rejects.toMatchObject({ code: "TERM_ALREADY_EXISTS" });
  });

  it("allows keeping the same term as a no-op term change", async () => {
    const wordId = await insertWord("hello");
    const detail = (await applyYoudaoContent(wordId, contentWithDefinition("你好"), "FILL_MISSING_FIELDS", [], "  hello "))!;
    expect(detail.term).toBe("hello");
    const row = await sqlite.prepare("SELECT term FROM words WHERE id = ?").get(wordId) as { term: string };
    expect(row.term).toBe("hello");
  });

  it("throws TERM_REQUIRED for a blank new term", async () => {
    const wordId = await insertWord("hello");
    await expect(applyYoudaoContent(wordId, contentWithDefinition("你好"), "FILL_MISSING_FIELDS", [], "   "))
      .rejects.toMatchObject({ code: "TERM_REQUIRED" });
  });

  it("leaves the term unchanged when newTerm is omitted", async () => {
    const wordId = await insertWord("hello");
    await applyYoudaoContent(wordId, contentWithDefinition("你好"), "FILL_MISSING_FIELDS", []);
    const row = await sqlite.prepare("SELECT term FROM words WHERE id = ?").get(wordId) as { term: string };
    expect(row.term).toBe("hello");
  });
});

describe("previewYoudaoContent termOverride", () => {
  it("fetches Youdao content for the overridden term", async () => {
    const wordId = await insertWord("hello");
    const fetchMock = vi.fn().mockResolvedValue(new Response(
      youdaoHtml("world", "英 [wɜːld]", "美 [wɝːld]", "简明", "n. 世界"),
      { status: 200 },
    ));
    vi.stubGlobal("fetch", fetchMock);
    await updateSettings({ youdaoEnabled: true });

    const result = await previewYoudaoContent(wordId, "world");

    expect(String(fetchMock.mock.calls[0]?.[0])).toContain("dict.youdao.com/w/eng/world");
    expect(result.hasContent).toBe(true);
    expect(result.content.definitions).toEqual([expect.objectContaining({ text: "世界" })]);
  });

  it("fetches the stored term when no override is provided", async () => {
    const wordId = await insertWord("hello");
    const fetchMock = vi.fn().mockResolvedValue(new Response(
      youdaoHtml("hello", "英 [həˈləʊ]", "美 [həˈloʊ]", "简明", "int. 你好"),
      { status: 200 },
    ));
    vi.stubGlobal("fetch", fetchMock);
    await updateSettings({ youdaoEnabled: true });

    const result = await previewYoudaoContent(wordId);

    expect(String(fetchMock.mock.calls[0]?.[0])).toContain("dict.youdao.com/w/eng/hello");
    expect(result.hasContent).toBe(true);
  });
});
