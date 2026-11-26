import { describe, expect, it } from "vitest";
import { evaluateReviewAnswer } from "@/modules/reviews/answer-evaluation";
import type { ReviewWordRow } from "@/modules/reviews/types";

const sentence: ReviewWordRow = {
  id: 1,
  term: "I have finished the work.",
  normalized_term: "i have finished the work.",
  source_language: "en",
  target_language: "zh-CN",
  content_type: "SENTENCE",
  initialization_status: "READY",
  is_suspended: 0,
  definitions_json: JSON.stringify([{ language: "zh-CN", text: "我已经完成工作了。" }]),
};

describe("sentence answer evaluation", () => {
  it("ignores sentence capitalization and terminal punctuation", () => {
    const result = evaluateReviewAnswer({
      clientAnswerId: crypto.randomUUID(),
      wordId: sentence.id,
      rating: "GOOD",
      questionType: "ZH_TO_EN_SPELLING",
      userAnswer: "i have finished the work",
    }, sentence);

    expect(result.isCorrect).toBe(true);
    expect(result.effectiveRating).toBe("GOOD");
    expect(result.presentedPrompt).toBe("我已经完成工作了。");
  });

  it("marks a materially different sentence wrong", () => {
    const result = evaluateReviewAnswer({
      clientAnswerId: crypto.randomUUID(),
      wordId: sentence.id,
      rating: "GOOD",
      questionType: "ZH_TO_EN_SPELLING",
      userAnswer: "I will finish the work.",
    }, sentence);

    expect(result.isCorrect).toBe(false);
    expect(result.effectiveRating).toBe("AGAIN");
  });
});
