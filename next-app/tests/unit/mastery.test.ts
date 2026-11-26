import { describe, expect, it } from "vitest";
import { calculateMasteryScore, determineMasteryLevel } from "@/modules/reviews/mastery";
import { mergeDictionaryContent, normalizeDictionaryContent } from "@/modules/dictionary/content";

describe("mastery", () => {
  it("keeps new cards at zero", () => {
    const input = { stability: 0, scheduledDays: 0, reps: 0, lapses: 0, accuracy: 0, consecutiveCorrect: 0, activeWrongWord: false, recentAgain: 0 };
    expect(calculateMasteryScore(input)).toBe(0);
    expect(determineMasteryLevel(input)).toBe("NEW");
  });

  it("marks strong long-term cards as mastered", () => {
    const input = { stability: 240, scheduledDays: 120, reps: 30, lapses: 0, accuracy: 0.96, consecutiveCorrect: 6, activeWrongWord: false, recentAgain: 0 };
    const score = calculateMasteryScore(input);
    expect(score).toBeGreaterThanOrEqual(85);
    expect(determineMasteryLevel(input, score)).toBe("MASTERED");
  });
});

describe("dictionary merge", () => {
  it("deduplicates structured related words without discarding definitions", () => {
    const merged = mergeDictionaryContent(
      {
        definitions: [{ language: "en", partOfSpeech: "n", text: "fabric", source: "a", isUserEdited: false }],
        synonyms: [{ word: "cloth", translation: "布", partOfSpeech: "n", relation: "SYNONYM", source: "a" }],
      },
      {
        definitions: [
          { language: "en", partOfSpeech: "n", text: "fabric", source: "b", isUserEdited: false },
          { language: "zh-CN", partOfSpeech: "n", text: "棉花", source: "b", isUserEdited: false },
        ],
        synonyms: [
          { word: "cloth", translation: null, partOfSpeech: "n", relation: "SYNONYM", source: "b" },
          { word: "fiber", translation: "纤维", partOfSpeech: "n", relation: "SYNONYM", source: "b" },
        ],
      },
    );
    expect(merged.definitions).toHaveLength(2);
    expect(merged.synonyms.map((item) => item.word)).toEqual(["cloth", "fiber"]);
  });

  it("upgrades legacy string synonyms from existing SQLite JSON", () => {
    const normalized = normalizeDictionaryContent({ synonyms: ["cloth", "fiber"] } as unknown as Record<string, unknown>);
    expect(normalized.synonyms).toEqual([
      { word: "cloth", translation: null, partOfSpeech: null, relation: "SYNONYM", source: "legacy" },
      { word: "fiber", translation: null, partOfSpeech: null, relation: "SYNONYM", source: "legacy" },
    ]);
  });
});
