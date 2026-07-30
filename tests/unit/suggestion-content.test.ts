import { describe, expect, it } from "vitest";
import { ruleBasedSuggestion } from "@/modules/suggestions/content";
import type { DailySuggestionMetrics, SuggestionCandidate } from "@/modules/suggestions/types";

const metrics: DailySuggestionMetrics = {
  reviewCount: 20,
  correctCount: 10,
  accuracy: 50,
  againCount: 5,
  hardCount: 3,
  skippedCount: 6,
  sessionCount: 1,
  averageDurationMs: 18_000,
  studyMinutes: 6,
  completionRate: 77,
  questionAccuracy: { ZH_TO_EN_SPELLING: 40, EN_TO_ZH: 80 },
};

const candidate: SuggestionCandidate = {
  wordId: 1,
  term: "fragile",
  definition: "脆弱的",
  reason: "昨天答错 2 次",
  questionType: "ZH_TO_EN_SPELLING",
  score: 200,
  attempts: 2,
  incorrect: 2,
  again: 1,
  hard: 0,
  wrongActive: true,
  overdueDays: 2,
};

describe("rule-based daily suggestion", () => {
  it("turns yesterday's weak signals into targeted actions", () => {
    const result = ruleBasedSuggestion(metrics, [candidate]);

    expect(result.headline).toBe("先修复错误，再恢复数量");
    expect(result.summary).toContain("答对 10 题");
    expect(result.risks).toEqual(expect.arrayContaining([
      "昨天正确率为 50%，需要优先修复错误而不是追求数量",
      "跳过了 6 题，复习任务出现积压",
    ]));
    expect(result.actions).toEqual(expect.arrayContaining([
      "今天暂缓增加新词，把时间集中在错词和拼写回忆",
      "把跳过的题拆成两小批完成，降低一次学习的负担",
    ]));
    expect(result.actions.every((action) => !action.includes("AI 必做题"))).toBe(true);
  });
});
