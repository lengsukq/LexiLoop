import { createEmptyCard, FSRS, Rating, State, type Card, type Grade, type RecordLogItem } from "ts-fsrs";
import type { ReviewRating } from "@/lib/types";

const fsrsInstances = new Map<number, FSRS>();

/** Creates (or reuses) an FSRS scheduler instance for the given target retention rate (0.7–0.99). */
function cachedFsrs(requestRetention: number): FSRS {
  let instance = fsrsInstances.get(requestRetention);
  if (!instance) {
    instance = new FSRS({
      request_retention: requestRetention,
      maximum_interval: 3650,
      enable_fuzz: true,
    });
    fsrsInstances.set(requestRetention, instance);
  }
  return instance;
}

/** Creates an FSRS scheduler instance with the given target retention rate (0.7–0.99). */
export function createFsrs(requestRetention = 0.9): FSRS {
  return cachedFsrs(requestRetention);
}

export function emptyCard(now = new Date()): Card {
  return createEmptyCard(now);
}

export function ratingToGrade(rating: ReviewRating): Grade {
  return {
    AGAIN: Rating.Again,
    HARD: Rating.Hard,
    GOOD: Rating.Good,
    EASY: Rating.Easy,
  }[rating] as Grade;
}

export function gradeToRating(grade: Grade): ReviewRating {
  const values: Record<number, ReviewRating> = {
    [Rating.Again]: "AGAIN",
    [Rating.Hard]: "HARD",
    [Rating.Good]: "GOOD",
    [Rating.Easy]: "EASY",
  };
  return values[grade] ?? "GOOD";
}

/** Schedules a card after a review, returning the updated card and log entry. */
export function scheduleCard(card: Card, now: Date, rating: ReviewRating, requestRetention = 0.9) {
  const result = createFsrs(requestRetention).repeat(card, now);
  const item = result[ratingToGrade(rating)] as RecordLogItem;
  return { card: item.card, log: item.log };
}

/** Previews all four rating outcomes for a card without mutating it. */
export function previewCard(card: Card, now: Date, requestRetention = 0.9) {
  const result = createFsrs(requestRetention).repeat(card, now);
  return ([Rating.Again, Rating.Hard, Rating.Good, Rating.Easy] as Grade[]).map((grade) => {
    const item = result[grade] as RecordLogItem;
    return {
      rating: gradeToRating(grade),
      nextDueAt: item.card.due,
      scheduledDays: item.card.scheduled_days,
    };
  });
}

/** Reconstructs a ts-fsrs Card from a database row. */
export function cardFromRow(row: {
  due_at: number;
  stability: number;
  difficulty: number;
  elapsed_days: number;
  scheduled_days: number;
  reps: number;
  lapses: number;
  fsrs_state: number;
  last_review_at: number | null;
  learning_steps: number;
}): Card {
  return {
    due: new Date(row.due_at),
    stability: row.stability,
    difficulty: row.difficulty,
    elapsed_days: row.elapsed_days,
    scheduled_days: row.scheduled_days,
    reps: row.reps,
    lapses: row.lapses,
    state: row.fsrs_state as State,
    last_review: row.last_review_at ? new Date(row.last_review_at) : undefined,
    learning_steps: row.learning_steps,
  };
}
