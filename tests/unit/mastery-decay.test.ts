import { describe, expect, it } from "vitest";
import { calculateMasteryScore, calculateRetrievability } from "@/modules/reviews/mastery";

describe("FSRS retrievability & mastery decay", () => {
  it("computes exact retrievability for on-due and overdue reviews", () => {
    // Exactly on due date: t = S, R = 1 / (1 + 1/9) = 0.90
    expect(calculateRetrievability(10, 10)).toBeCloseTo(0.90, 2);
    expect(calculateRetrievability(30, 30)).toBeCloseTo(0.90, 2);

    // Immediate review: t = 0, R = 1.0
    expect(calculateRetrievability(0, 10)).toBe(1.0);

    // Overdue review: t = 3 * S, R = 1 / (1 + 3/9) = 0.75
    expect(calculateRetrievability(30, 10)).toBeCloseTo(0.75, 2);

    // Vastly overdue review: t = 9 * S, R = 1 / (1 + 9/9) = 0.50
    expect(calculateRetrievability(90, 10)).toBeCloseTo(0.50, 2);
  });

  it("decays mastery score when cards are significantly overdue", () => {
    const input = {
      stability: 10,
      scheduledDays: 10,
      reps: 5,
      lapses: 0,
      accuracy: 1.0,
      consecutiveCorrect: 5,
      activeWrongWord: false,
      recentAgain: 0,
    };

    const freshScore = calculateMasteryScore(input);
    const onDueScore = calculateMasteryScore(input, 10);
    const overdueScore = calculateMasteryScore(input, 40);

    expect(freshScore).toBeGreaterThan(0);
    expect(onDueScore).toBe(freshScore); // On due date (R=0.9), retention multiplier is 1.0
    expect(overdueScore).toBeLessThan(onDueScore); // Significantly overdue cards have lower retrievability
  });
});
