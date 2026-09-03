import { describe, expect, it } from "vitest";
import {
  articleCandidateKey,
  fallbackRecommendedTerms,
  initialSelectionKeys,
  mergeArticleCandidates,
  recommendedCandidateKeys,
} from "@/modules/article-import/candidates";
import type { ArticleCandidate } from "@/lib/types/article-import";

function candidate(overrides: Partial<ArticleCandidate> & { term: string; normalizedTerm: string }): ArticleCandidate {
  return {
    occurrences: 1,
    status: "CANDIDATE",
    entryType: "WORD",
    sourceSentence: null,
    aiReason: null,
    difficulty: null,
    cefrLevel: null,
    frequency: null,
    aiCard: null,
    ...overrides,
  };
}

describe("articleCandidateKey", () => {
  it("keeps WORD/PHRASE/SENTENCE apart for the same text", () => {
    const word = articleCandidateKey(candidate({ term: "Take off", normalizedTerm: "take off", entryType: "WORD" }));
    const phrase = articleCandidateKey(candidate({ term: "Take off", normalizedTerm: "take off", entryType: "PHRASE" }));
    expect(word).not.toBe(phrase);
  });

  it("normalizes case and unicode before keying", () => {
    const a = articleCandidateKey(candidate({ term: "Apple", normalizedTerm: "Apple" }));
    const b = articleCandidateKey(candidate({ term: "apple", normalizedTerm: "apple" }));
    expect(a).toBe(b);
  });
});

describe("mergeArticleCandidates", () => {
  it("dedupes by key, summing occurrences and keeping the strongest signal", () => {
    const merged = mergeArticleCandidates([
      candidate({ term: "apple", normalizedTerm: "apple", occurrences: 2, difficulty: 3 }),
      candidate({ term: "Apple", normalizedTerm: "apple", occurrences: 3, difficulty: 7, aiReason: "core vocab", cefrLevel: "B1" }),
    ]);
    expect(merged).toHaveLength(1);
    expect(merged[0]).toMatchObject({ occurrences: 5, difficulty: 7, aiReason: "core vocab", cefrLevel: "B1" });
  });

  it("upgrades to KNOWN when any segment saw the word", () => {
    const merged = mergeArticleCandidates([
      candidate({ term: "run", normalizedTerm: "run", status: "CANDIDATE" }),
      candidate({ term: "run", normalizedTerm: "run", status: "KNOWN" }),
    ]);
    expect(merged[0]?.status).toBe("KNOWN");
  });
});

describe("fallbackRecommendedTerms / recommendedCandidateKeys", () => {
  it("prefers AI-picked words, otherwise takes the first N candidate words", () => {
    const withAi = [
      candidate({ term: "ubiquitous", normalizedTerm: "ubiquitous", aiReason: "worth learning" }),
      candidate({ term: "the", normalizedTerm: "the" }),
    ];
    expect(fallbackRecommendedTerms(withAi)).toEqual(["ubiquitous"]);

    const plain = [
      candidate({ term: "a", normalizedTerm: "a" }),
      candidate({ term: "b", normalizedTerm: "b" }),
    ];
    expect(fallbackRecommendedTerms(plain, 1)).toEqual(["a"]);
  });

  it("selects recommended words plus every candidate phrase and sentence", () => {
    const merged = [
      candidate({ term: "ubiquitous", normalizedTerm: "ubiquitous" }),
      candidate({ term: "other", normalizedTerm: "other" }),
      candidate({ term: "take off", normalizedTerm: "take off", entryType: "PHRASE" }),
      candidate({ term: "I love you.", normalizedTerm: "i love you.", entryType: "SENTENCE" }),
    ];
    const keys = recommendedCandidateKeys(merged, ["ubiquitous"]);
    expect(keys).toHaveLength(3);
    expect(keys.some((k) => k.includes("other"))).toBe(false);
  });
});

describe("initialSelectionKeys", () => {
  it("uses server recommendedKeys when present", () => {
    const keys = initialSelectionKeys({
      recommendedKeys: ["WORD\u0000apple"],
      recommendedTerms: [],
      candidates: [candidate({ term: "apple", normalizedTerm: "apple" })],
    });
    expect([...keys]).toEqual(["word\u0000apple"]);
  });

  it("rebuilds from candidates when the server sent no keys", () => {
    const keys = initialSelectionKeys({
      recommendedTerms: [],
      candidates: [
        candidate({ term: "apple", normalizedTerm: "apple" }),
        candidate({ term: "take off", normalizedTerm: "take off", entryType: "PHRASE" }),
      ],
    });
    expect(keys.size).toBe(2);
  });
});
