import { describe, expect, it } from "vitest";
import { AI_SELECTION_JSON_SCHEMA, normalizeLegacyResponse } from "@/modules/article-import/schema";

describe("normalizeLegacyResponse (lenient)", () => {
  it("accepts a fully valid response unchanged", () => {
    const parsed = {
      words: [{ term: "ubiquitous", reason: "高频学术词", difficulty: 4, cefrLevel: "C1", frequency: "NORMAL" }],
      phrases: [],
      sentences: [],
    };
    const result = normalizeLegacyResponse(parsed);
    expect(result?.words?.[0]).toMatchObject({ term: "ubiquitous", difficulty: 4 });
  });

  it("clamps over-length fields instead of rejecting the whole batch", () => {
    const parsed = {
      words: [{ term: "serendipity", reason: "x".repeat(120), difficulty: 9, cefrLevel: "Z9" }],
      phrases: [],
      sentences: [],
    };
    const result = normalizeLegacyResponse(parsed);
    expect(result?.words?.[0]?.term).toBe("serendipity");
    expect(result?.words?.[0]?.reason).toHaveLength(40);
    expect(result?.words?.[0]?.difficulty).toBe(5);
    expect(result?.words?.[0]?.cefrLevel).toBeNull();
  });

  it("fills defaults for missing optional fields", () => {
    const parsed = {
      phrases: [{ term: "take off", literalTranslation: "拿走", freeTranslation: "起飞" }],
      sentences: [],
    };
    const result = normalizeLegacyResponse(parsed);
    expect(result?.phrases?.[0]).toMatchObject({ term: "take off", difficulty: 3 });
    expect(result?.words).toHaveLength(0);
  });

  it("accepts the legacy selected[] shape", () => {
    const parsed = { selected: [{ term: "run", reason: "动词", difficulty: 2 }] };
    const result = normalizeLegacyResponse(parsed);
    expect(result?.words?.[0]?.term).toBe("run");
  });

  it("matches keys case-insensitively and drops malformed items", () => {
    const parsed = {
      Words: [{ term: "apple" }, { noTerm: true }, "junk", 42],
      PHRASES: [],
      Sentences: [],
    };
    const result = normalizeLegacyResponse(parsed);
    expect(result?.words?.map((w) => w.term)).toEqual(["apple"]);
  });

  it("returns null for empty or non-object input", () => {
    expect(normalizeLegacyResponse(null)).toBeNull();
    expect(normalizeLegacyResponse("text")).toBeNull();
    expect(normalizeLegacyResponse({ words: [], phrases: [], sentences: [] })).toBeNull();
  });

  it("exposes a strict-mode compatible JSON schema", () => {
    // OpenAI strict 模式要求 properties 中每个 key 都出现在 required 中
    const root = AI_SELECTION_JSON_SCHEMA as unknown as { required: string[]; properties: Record<string, unknown> };
    for (const key of Object.keys(root.properties)) expect(root.required).toContain(key);
    const wordsItems = (root.properties.words as { items: { required: string[]; properties: Record<string, unknown> } }).items;
    for (const key of Object.keys(wordsItems.properties)) expect(wordsItems.required).toContain(key);
  });
});
