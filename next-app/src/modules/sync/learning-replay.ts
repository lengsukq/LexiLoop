import { createEmptyCard, FSRS, type Card, type RecordLogItem } from "ts-fsrs";
import { localDayOrdinal } from "@/lib/date-key";
import { DAY_MS } from "@/lib/time";
import type { MasteryLevel, ReviewRating } from "@/lib/types";
import { ratingToGrade } from "@/modules/reviews/fsrs";
import { calculateMasteryScore, determineMasteryLevel } from "@/modules/reviews/mastery";

const MASTERY_WINDOW_MS = 30 * DAY_MS;

export interface ReplayLogEntry {
  reviewedAt: number;
  rating: ReviewRating;
  isCorrect: boolean;
  durationMs: number | null;
}

export interface ReplayedWrongState {
  active: boolean;
  wrongCount: number;
  hardCount: number;
  consecutiveCorrect: number;
  lastWrongAt: number | null;
  lastCorrectAt: number | null;
  resolvedAt: number | null;
}

export interface ReplayedWordState {
  card: Card;
  wrong: ReplayedWrongState | null;
  masteryScore: number;
  masteryLevel: MasteryLevel;
}

/** Deterministic FSRS scheduler (`enable_fuzz: false`) aligned with Flutter's `FsrsScheduler`. */
export function createDeterministicFsrs(requestRetention = 0.9): FSRS {
  const clamped = Math.min(0.99, Math.max(0.7, requestRetention));
  return new FSRS({
    request_retention: clamped,
    maximum_interval: 3650,
    enable_fuzz: false,
  });
}

function nextConsecutiveCorrect(current: ReplayedWrongState, now: number): number {
  const previousDay = current.lastCorrectAt !== null ? localDayOrdinal(current.lastCorrectAt) : null;
  const dayGap = previousDay === null ? null : localDayOrdinal(now) - previousDay;
  if (dayGap === 0) return current.consecutiveCorrect;
  if (dayGap === 1) return current.consecutiveCorrect + 1;
  return 1;
}

/** Pure transition aligned with `src/modules/reviews/wrong-state.ts` and Flutter `wrong_state.dart`. */
export function transitionWrongStatePure(
  current: ReplayedWrongState | null,
  rating: ReviewRating,
  isCorrect: boolean,
  now: number,
): ReplayedWrongState | null {
  if (rating === "EASY") {
    if (!current) return null;
    return {
      ...current,
      active: false,
      consecutiveCorrect: 1,
      lastCorrectAt: now,
      resolvedAt: now,
    };
  }
  if (!isCorrect || rating === "AGAIN") {
    return {
      active: true,
      wrongCount: (current?.wrongCount ?? 0) + 1,
      hardCount: current?.hardCount ?? 0,
      consecutiveCorrect: 0,
      lastWrongAt: now,
      lastCorrectAt: current?.lastCorrectAt ?? null,
      resolvedAt: null,
    };
  }
  if (rating === "HARD") {
    return {
      active: true,
      wrongCount: current?.wrongCount ?? 0,
      hardCount: (current?.hardCount ?? 0) + 1,
      consecutiveCorrect: 0,
      lastWrongAt: current?.lastWrongAt ?? null,
      lastCorrectAt: current?.lastCorrectAt ?? null,
      resolvedAt: null,
    };
  }
  if (!current) return null;

  const consecutiveCorrect = nextConsecutiveCorrect(current, now);
  const currentDay = localDayOrdinal(now);
  const oldEnough = current.lastWrongAt === null || currentDay - localDayOrdinal(current.lastWrongAt) >= 2;
  const resolved = consecutiveCorrect >= 3 && oldEnough;
  return {
    active: resolved ? false : current.active,
    wrongCount: current.wrongCount,
    hardCount: current.hardCount,
    consecutiveCorrect,
    lastWrongAt: current.lastWrongAt,
    lastCorrectAt: now,
    resolvedAt: resolved ? now : null,
  };
}

/**
 * Deterministically replays all review logs for a single word (ordered by `reviewed_at, client_answer_id`)
 * to derive consistent `review_cards`, `wrong_word_states`, and `words.mastery_*`.
 */
export function replayWordHistory(
  logs: readonly ReplayLogEntry[],
  requestRetention: number,
  now: number,
): ReplayedWordState {
  if (logs.length === 0) {
    throw new Error("replayWordHistory requires at least one review log");
  }
  const fsrs = createDeterministicFsrs(requestRetention);
  let card: Card = createEmptyCard(new Date(logs[0]!.reviewedAt));
  let wrong: ReplayedWrongState | null = null;

  let total = 0;
  let correct = 0;
  let recentAgain = 0;
  let durationTotal = 0;
  let durationCount = 0;
  const since30 = now - MASTERY_WINDOW_MS;

  for (const log of logs) {
    const result = fsrs.repeat(card, new Date(log.reviewedAt));
    card = (result[ratingToGrade(log.rating)] as RecordLogItem).card;
    const nextWrong = transitionWrongStatePure(wrong, log.rating, log.isCorrect, log.reviewedAt);
    if (nextWrong !== null) wrong = nextWrong;

    total += 1;
    if (log.isCorrect) correct += 1;
    if (log.rating === "AGAIN" && log.reviewedAt >= since30) recentAgain += 1;
    if (log.durationMs !== null && log.durationMs > 0) {
      durationTotal += log.durationMs;
      durationCount += 1;
    }
  }

  const masteryInput = {
    stability: card.stability,
    scheduledDays: card.scheduled_days,
    reps: card.reps,
    lapses: card.lapses,
    accuracy: total > 0 ? correct / total : 0,
    consecutiveCorrect: wrong?.consecutiveCorrect ?? 1,
    activeWrongWord: wrong?.active ?? false,
    recentAgain,
    avgDurationMs: durationCount > 0 ? durationTotal / durationCount : undefined,
  };
  const masteryScore = calculateMasteryScore(masteryInput);
  const masteryLevel = determineMasteryLevel(masteryInput, masteryScore);
  return { card, wrong, masteryScore, masteryLevel };
}
