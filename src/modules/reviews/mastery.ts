import type { MasteryLevel } from "@/lib/types";

/**
 * Inputs for mastery calculation. Combines FSRS card state,
 * historical accuracy, wrong-word status, and response speed.
 */
export interface MasteryInput {
  stability: number;
  scheduledDays: number;
  reps: number;
  lapses: number;
  accuracy: number;
  consecutiveCorrect: number;
  activeWrongWord: boolean;
  recentAgain: number;
  avgDurationMs?: number;
}

/**
 * Calculates a 0-100 mastery score using weighted components:
 * - Stability (30): FSRS memory stability, log-scaled
 * - Accuracy (25): historical correct rate
 * - Interval (18): current scheduled interval length
 * - Streak (10): consecutive correct answers
 * - Experience (7): total review repetitions
 * - Speed bonus (10): faster correct recalls score higher
 * - Penalty (-25 max): lapses, recent AGAIN ratings, active wrong words
 */
export function calculateMasteryScore(input: MasteryInput): number {
  if (input.reps === 0) return 0;
  const stability = Math.min(30, Math.log1p(Math.max(0, input.stability)) / Math.log1p(365) * 30);
  const accuracy = Math.max(0, Math.min(1, input.accuracy)) * 25;
  const interval = Math.min(18, Math.max(0, input.scheduledDays) / 90 * 18);
  const streak = Math.min(10, Math.max(0, input.consecutiveCorrect) / 5 * 10);
  const experience = Math.min(7, input.reps / 20 * 7);
  const speedBonus = input.avgDurationMs != null && input.avgDurationMs > 0
    ? Math.min(10, Math.max(0, (1 - input.avgDurationMs / 15000)) * 10)
    : 0;
  const penalty = Math.min(25, input.lapses * 3 + input.recentAgain * 2 + (input.activeWrongWord ? 5 : 0));
  return Math.round(Math.max(0, Math.min(100, stability + accuracy + interval + streak + experience + speedBonus - penalty)));
}

/** Maps a numeric mastery score to a discrete level: NEW → LEARNING → FAMILIAR → PROFICIENT → MASTERED */
export function determineMasteryLevel(input: MasteryInput, score = calculateMasteryScore(input)): MasteryLevel {
  if (input.reps === 0) return "NEW";
  if (input.activeWrongWord || input.reps < 3 || input.scheduledDays < 7 || score < 40) return "LEARNING";
  if (input.scheduledDays >= 90 && input.accuracy >= 0.9 && input.recentAgain === 0 && score >= 85) return "MASTERED";
  if (input.scheduledDays >= 30 && input.accuracy >= 0.8 && input.recentAgain === 0 && score >= 70) return "PROFICIENT";
  if (input.scheduledDays >= 7 && input.accuracy >= 0.7 && score >= 45) return "FAMILIAR";
  return "LEARNING";
}
