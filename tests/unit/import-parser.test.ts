import { describe, expect, it } from "vitest";
import { detectEntryType, displayTerm, normalizeTerm } from "@/modules/imports/normalizer";
import { parseEasyDictCsv } from "@/modules/imports/parser";

describe("EasyDict parser and normalization", () => {
  it("normalizes latin terms and detects phrases", () => {
    expect(normalizeTerm("  BROCHURE  ", "en")).toBe("brochure");
    expect(normalizeTerm("take   care of", "en")).toBe("take care of");
    expect(detectEntryType("take care of")).toBe("PHRASE");
    expect(detectEntryType("well-known")).toBe("WORD");
  });

  it("detects complete short and long sentences without turning common phrases into sentences", () => {
    expect(detectEntryType("I love you")).toBe("SENTENCE");
    expect(detectEntryType("How are you?")).toBe("SENTENCE");
    expect(detectEntryType("She wants to learn English")).toBe("SENTENCE");
    expect(detectEntryType("in front of")).toBe("PHRASE");
    expect(detectEntryType("as soon as possible")).toBe("PHRASE");
  });

  it("lowercases only single words, keeping phrases and sentences untouched", () => {
    expect(displayTerm("BROCHURE", "en", "WORD")).toBe("brochure");
    expect(displayTerm("well-known", "en", "WORD")).toBe("well-known");
    expect(displayTerm("Take Care", "en", "PHRASE")).toBe("Take Care");
    expect(displayTerm("I Love You", "en", "SENTENCE")).toBe("I Love You");
    expect(displayTerm("Apple", "de", "WORD")).toBe("apple");
    expect(displayTerm("苹果", "zh-CN", "WORD")).toBe("苹果");
  });

  it("requires EasyDict headers", () => {
    const result = parseEasyDictCsv("word,language\nhello,en\n");
    expect(result.parseErrors[0]).toContain("缺少必要列");
  });

  it("parses valid and invalid rows separately", () => {
    const result = parseEasyDictCsv("queryText,queryFromLanguage,queryToLanguage,timestamp\nhello,English,Simplified Chinese,2026-01-01\n,English,Simplified Chinese,invalid\n");
    expect(result.rows).toHaveLength(2);
    expect(result.rows[0]?.data?.queryText).toBe("hello");
    expect(result.rows[1]?.errors.length).toBeGreaterThan(0);
  });
});
