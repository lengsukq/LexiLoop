import type { MasteryLevel } from "@/lib/types";

export interface MasteryInput {
  stability: number;
  scheduledDays: number;
  reps: number;
  lapses: number;
  accuracy: number;
  consecutiveCorrect: number;
  activeWrongWord: boolean;
  recentAgain: number;
}

export function calculateMasteryScore(input: MasteryInput): number {
  if (input.reps === 0) return 0;
  const stability = Math.min(35, Math.log1p(Math.max(0, input.stability)) / Math.log1p(365) * 35);
  const accuracy = Math.max(0, Math.min(1, input.accuracy)) * 25;
  const interval = Math.min(20, Math.max(0, input.scheduledDays) / 90 * 20);
  const streak = Math.min(10, Math.max(0, input.consecutiveCorrect) / 5 * 10);
  const experience = Math.min(10, input.reps / 20 * 10);
  const penalty = Math.min(25, input.lapses * 3 + input.recentAgain * 2 + (input.activeWrongWord ? 5 : 0));
  return Math.round(Math.max(0, Math.min(100, stability + accuracy + interval + streak + experience - penalty)));
}

export function determineMasteryLevel(input: MasteryInput, score = calculateMasteryScore(input)): MasteryLevel {
  if (input.reps === 0) return "NEW";
  if (input.activeWrongWord || input.reps < 3 || input.scheduledDays < 7 || score < 40) return "LEARNING";
  if (input.scheduledDays >= 90 && input.accuracy >= 0.9 && input.recentAgain === 0 && score >= 85) return "MASTERED";
  if (input.scheduledDays >= 30 && input.accuracy >= 0.8 && input.recentAgain === 0 && score >= 70) return "PROFICIENT";
  if (input.scheduledDays >= 7 && input.accuracy >= 0.7 && score >= 45) return "FAMILIAR";
  return "LEARNING";
}
