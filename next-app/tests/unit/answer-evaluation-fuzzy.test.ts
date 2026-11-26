import { describe, expect, it } from "vitest";
import { isAnswerCorrect, levenshteinDistance, normalizeSentenceAnswer } from "@/modules/reviews/answer-evaluation";
import type { ReviewWordRow } from "@/modules/reviews/types";

describe("answer-evaluation fuzzy matching", () => {
  it("calculates correct Levenshtein distance", () => {
    expect(levenshteinDistance("kitten", "sitting")).toBe(3);
    expect(levenshteinDistance("meticulous", "meticulus")).toBe(1);
    expect(levenshteinDistance("hello", "hello")).toBe(0);
    expect(levenshteinDistance("", "abc")).toBe(3);
  });

  it("normalizes English contractions and US/UK spelling variants in sentences", () => {
    expect(normalizeSentenceAnswer("I'm happy.")).toBe("i am happy");
    expect(normalizeSentenceAnswer("I am happy")).toBe("i am happy");
    expect(normalizeSentenceAnswer("We've completed the task.")).toBe("we have completed the task");
    expect(normalizeSentenceAnswer("We have completed the task.")).toBe("we have completed the task");
    expect(normalizeSentenceAnswer("The colour of the centre")).toBe("the color of the center");
  });

  it("accepts equivalent sentence contractions and minor typo", () => {
    const word: ReviewWordRow = {
      id: 1,
      term: "I have been working here for five years.",
      normalized_term: "i have been working here for five years.",
      source_language: "en",
      target_language: "zh-CN",
      content_type: "SENTENCE",
      definitions_json: "[]",
      initialization_status: "READY",
      is_suspended: 0,
    };

    // User types "I've been working here for five years"
    expect(isAnswerCorrect({
      clientAnswerId: "1",
      wordId: 1,
      questionType: "ZH_TO_EN_SPELLING",
      rating: "GOOD",
      userAnswer: "I've been working here for five years.",
    }, word, [])).toBe(true);

    // User types "I have been working here for five years" (no punctuation)
    expect(isAnswerCorrect({
      clientAnswerId: "2",
      wordId: 1,
      questionType: "ZH_TO_EN_SPELLING",
      rating: "GOOD",
      userAnswer: "i have been working here for five years",
    }, word, [])).toBe(true);
  });

  it("accepts minor single-character typo on long words", () => {
    const word: ReviewWordRow = {
      id: 2,
      term: "meticulous",
      normalized_term: "meticulous",
      source_language: "en",
      target_language: "zh-CN",
      content_type: "WORD",
      definitions_json: "[]",
      initialization_status: "READY",
      is_suspended: 0,
    };

    // Minor typo "meticulus" (missing o) on a 10-char word
    expect(isAnswerCorrect({
      clientAnswerId: "3",
      wordId: 2,
      questionType: "ZH_TO_EN_SPELLING",
      rating: "GOOD",
      userAnswer: "meticulus",
    }, word, [])).toBe(true);

    // Far-off answer "met" should still fail
    expect(isAnswerCorrect({
      clientAnswerId: "4",
      wordId: 2,
      questionType: "ZH_TO_EN_SPELLING",
      rating: "GOOD",
      userAnswer: "met",
    }, word, [])).toBe(false);
  });

  it("accepts US and UK spelling variations for words", () => {
    const word: ReviewWordRow = {
      id: 3,
      term: "color",
      normalized_term: "color",
      source_language: "en",
      target_language: "zh-CN",
      content_type: "WORD",
      definitions_json: "[]",
      initialization_status: "READY",
      is_suspended: 0,
    };

    expect(isAnswerCorrect({
      clientAnswerId: "5",
      wordId: 3,
      questionType: "ZH_TO_EN_SPELLING",
      rating: "GOOD",
      userAnswer: "colour",
    }, word, [])).toBe(true);
  });
});
