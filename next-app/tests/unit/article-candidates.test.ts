import { describe, expect, it } from "vitest";
import {
  articleCandidateKey,
  fallbackRecommendedTerms,
  initialSelectionKeys,
  mergeAiErrors,
  mergeArticleCandidates,
  mergeArticlePreviews,
  recommendedCandidateKeys,
} from "@/modules/article-import/candidates";
import type { ArticleCandidate, ArticleImportPreview } from "@/lib/types/article-import";

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

function preview(overrides: Partial<ArticleImportPreview> & { previewToken: string }): ArticleImportPreview {
  return {
    filename: "article:test",
    articleStats: { charCount: 100, wordCount: 20, uniqueCount: 10, knownCount: 0, unknownCount: 10, phraseCount: 0, sentenceCount: 0 },
    candidates: [],
    recommendedTerms: [],
    recommendedKeys: [],
    aiApplied: false,
    aiError: null,
    totalCandidates: 0,
    knownCount: 0,
    expiresAt: new Date(Date.now() + 60_000).toISOString(),
    ...overrides,
  };
}

describe("mergeAiErrors", () => {
  it("keeps one message per failing token (shared-batch segments dedupe)", () => {
    const token = "11111111-1111-1111-1111-111111111111";
    const message = "AI 返回格式不符合预期，已回退为本地筛选。";
    const merged = mergeAiErrors([
      { previewToken: token, aiError: message },
      { previewToken: token, aiError: message },
      { previewToken: token, aiError: message },
      { previewToken: token, aiError: message },
    ]);
    expect(merged).toBe(message);
  });

  it("joins distinct messages and ignores empty errors", () => {
    const merged = mergeAiErrors([
      { previewToken: "22222222-2222-2222-2222-222222222222", aiError: "超时" },
      { previewToken: "33333333-3333-3333-3333-333333333333", aiError: null },
      { previewToken: "44444444-4444-4444-4444-444444444444", aiError: "格式错误" },
    ]);
    expect(merged).toBe("超时；格式错误");
  });
});

describe("mergeArticlePreviews", () => {
  it("dedupes by previewToken so shared-batch previews do not double stats or errors", () => {
    const token = "55555555-5555-5555-5555-555555555555";
    const message = "AI 返回格式不符合预期，已回退为本地筛选。";
    const shared = preview({
      previewToken: token,
      aiError: message,
      articleStats: { charCount: 3000, wordCount: 500, uniqueCount: 40, knownCount: 2, unknownCount: 38, phraseCount: 1, sentenceCount: 1 },
      candidates: [
        candidate({ term: "apple", normalizedTerm: "apple", occurrences: 2 }),
        candidate({ term: "take off", normalizedTerm: "take off", entryType: "PHRASE", occurrences: 1 }),
      ],
    });
    const merged = mergeArticlePreviews([shared, shared, shared, shared]);
    expect(merged).not.toBeNull();
    expect(merged!.articleStats.charCount).toBe(3000);
    expect(merged!.articleStats.wordCount).toBe(500);
    expect(merged!.candidates.find((c) => c.entryType === "WORD")?.occurrences).toBe(2);
    expect(merged!.aiError).toBe(message);
  });

  it("merges distinct tokens summing stats and joining errors", () => {
    const message = "AI 返回格式不符合预期，已回退为本地筛选。";
    const a = preview({
      previewToken: "66666666-6666-6666-6666-666666666666",
      aiError: message,
      articleStats: { charCount: 2000, wordCount: 300, uniqueCount: 20, knownCount: 0, unknownCount: 20, phraseCount: 0, sentenceCount: 0 },
      candidates: [candidate({ term: "apple", normalizedTerm: "apple", occurrences: 3 })],
    });
    const b = preview({
      previewToken: "77777777-7777-7777-7777-777777777777",
      aiError: message,
      articleStats: { charCount: 1500, wordCount: 200, uniqueCount: 15, knownCount: 1, unknownCount: 14, phraseCount: 0, sentenceCount: 0 },
      candidates: [candidate({ term: "Apple", normalizedTerm: "apple", occurrences: 4 })],
    });
    const merged = mergeArticlePreviews([a, b]);
    expect(merged!.articleStats.charCount).toBe(3500);
    expect(merged!.articleStats.wordCount).toBe(500);
    expect(merged!.candidates.find((c) => c.entryType === "WORD")?.occurrences).toBe(7);
    expect(merged!.aiError).toBe(`${message}（2 批）`);
  });
});
