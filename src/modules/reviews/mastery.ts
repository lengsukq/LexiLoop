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
  elapsedDays?: number;
}

const FSRS_DECAY_FACTOR = 1 / 9; // Standard FSRS decay coefficient where R(S) = 1 / (1 + 1/9) = 0.90

/**
 * Calculates real-time memory retrievability R(t) in [0.05, 1.0] based on FSRS power forgetting curve.
 * - At t = 0 (just reviewed): R = 1.0
 * - At t = S (on due date): R = 0.90
 * - As t grows overdue: R decays smoothly, reflecting actual brain memory retrievability
 */
export function calculateRetrievability(elapsedDays: number, stability: number): number {
  if (stability <= 0 || elapsedDays <= 0) return 1.0;
  return Math.max(0.05, Math.min(1.0, 1 / (1 + (FSRS_DECAY_FACTOR * elapsedDays) / stability)));
}

/** Weight of each score component (out of 100; penalty is subtracted). */
const MASTERY_WEIGHTS = {
  stability: 30,
  accuracy: 25,
  interval: 18,
  streak: 10,
  experience: 7,
  speed: 10,
  penaltyCap: 25,
} as const;

/** Denominators that normalize each component to its "full" scale. */
const MASTERY_SCALES = {
  stabilityFullDays: 365,
  intervalFullDays: 90,
  streakFullCount: 5,
  experienceFullReps: 20,
  speedBaselineMs: 15000,
} as const;

/** Per-unit penalties applied when the learner is struggling. */
const MASTERY_PENALTIES = {
  lapse: 3,
  recentAgain: 2,
  activeWrongWord: 5,
} as const;

/** Score / accuracy / interval gates used by determineMasteryLevel. */
const MASTERY_THRESHOLDS = {
  minReps: 3,
  minScheduledDays: 7,
  learningScore: 40,
  familiarScore: 45,
  proficientScore: 70,
  masteredScore: 85,
  proficientDays: 30,
  masteredDays: 90,
  familiarAccuracy: 0.7,
  proficientAccuracy: 0.8,
  masteredAccuracy: 0.9,
} as const;

/**
 * Calculates a 0-100 mastery score using weighted components:
 * - Stability (30): FSRS memory stability, log-scaled
 * - Accuracy (25): historical correct rate
 * - Interval (18): current scheduled interval length
 * - Streak (10): consecutive correct answers
 * - Experience (7): total review repetitions
 * - Speed bonus (10): faster correct recalls score higher
 * - Penalty (-25 max): lapses, recent AGAIN ratings, active wrong words
 * - Retrievability decay: smoothly modulates score when cards are overdue
 */
export function calculateMasteryScore(input: MasteryInput, elapsedDays?: number): number {
  if (input.reps === 0) return 0;
  const stability = Math.min(MASTERY_WEIGHTS.stability, Math.log1p(Math.max(0, input.stability)) / Math.log1p(MASTERY_SCALES.stabilityFullDays) * MASTERY_WEIGHTS.stability);
  const accuracy = Math.max(0, Math.min(1, input.accuracy)) * MASTERY_WEIGHTS.accuracy;
  const interval = Math.min(MASTERY_WEIGHTS.interval, Math.max(0, input.scheduledDays) / MASTERY_SCALES.intervalFullDays * MASTERY_WEIGHTS.interval);
  const streak = Math.min(MASTERY_WEIGHTS.streak, Math.max(0, input.consecutiveCorrect) / MASTERY_SCALES.streakFullCount * MASTERY_WEIGHTS.streak);
  const experience = Math.min(MASTERY_WEIGHTS.experience, input.reps / MASTERY_SCALES.experienceFullReps * MASTERY_WEIGHTS.experience);
  const speedBonus = input.avgDurationMs != null && input.avgDurationMs > 0
    ? Math.min(MASTERY_WEIGHTS.speed, Math.max(0, (1 - input.avgDurationMs / MASTERY_SCALES.speedBaselineMs)) * MASTERY_WEIGHTS.speed)
    : 0;
  const penalty = Math.min(MASTERY_WEIGHTS.penaltyCap, input.lapses * MASTERY_PENALTIES.lapse + input.recentAgain * MASTERY_PENALTIES.recentAgain + (input.activeWrongWord ? MASTERY_PENALTIES.activeWrongWord : 0));
  const rawScore = Math.max(0, Math.min(100, stability + accuracy + interval + streak + experience + speedBonus - penalty));

  const daysElapsed = elapsedDays ?? input.elapsedDays;
  if (daysElapsed != null && daysElapsed > 0 && input.stability > 0) {
    const retrievability = calculateRetrievability(daysElapsed, input.stability);
    const retentionMultiplier = Math.min(1.0, Math.max(0.3, retrievability / 0.9));
    return Math.round(rawScore * retentionMultiplier);
  }

  return Math.round(rawScore);
}

/** Maps a numeric mastery score to a discrete level: NEW → LEARNING → FAMILIAR → PROFICIENT → MASTERED */
export function determineMasteryLevel(input: MasteryInput, score = calculateMasteryScore(input)): MasteryLevel {
  if (input.reps === 0) return "NEW";
  if (input.activeWrongWord || input.reps < MASTERY_THRESHOLDS.minReps || input.scheduledDays < MASTERY_THRESHOLDS.minScheduledDays || score < MASTERY_THRESHOLDS.learningScore) return "LEARNING";
  if (input.scheduledDays >= MASTERY_THRESHOLDS.masteredDays && input.accuracy >= MASTERY_THRESHOLDS.masteredAccuracy && input.recentAgain === 0 && score >= MASTERY_THRESHOLDS.masteredScore) return "MASTERED";
  if (input.scheduledDays >= MASTERY_THRESHOLDS.proficientDays && input.accuracy >= MASTERY_THRESHOLDS.proficientAccuracy && input.recentAgain === 0 && score >= MASTERY_THRESHOLDS.proficientScore) return "PROFICIENT";
  if (input.scheduledDays >= MASTERY_THRESHOLDS.minScheduledDays && input.accuracy >= MASTERY_THRESHOLDS.familiarAccuracy && score >= MASTERY_THRESHOLDS.familiarScore) return "FAMILIAR";
  return "LEARNING";
}
