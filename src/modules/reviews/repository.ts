import { sqlite } from "@/db/client";
import type { MasteryLevel, ReviewRating } from "@/lib/types";
import type { Card } from "ts-fsrs";
import type {
  AnswerInput,
  ExistingReviewLog,
  ReviewCardRow,
  ReviewStatistics,
  ReviewWordRow,
} from "./types";
import { boundedActiveDurationMs, closeStudySessionWithActiveDuration } from "./duration";

const MASTERY_WINDOW_MS = 30 * 24 * 60 * 60 * 1000;
const PERFORMANCE_WINDOW_MS = 14 * 24 * 60 * 60 * 1000;

export function findExistingReview(clientAnswerId: string): ExistingReviewLog | undefined {
  return sqlite.prepare(`SELECT id, word_id, study_session_id, study_session_item_id,
    rating, is_correct, expected_answer FROM review_logs WHERE client_answer_id = ?`)
    .get(clientAnswerId) as ExistingReviewLog | undefined;
}

export function assertIdempotencyContext(existing: ExistingReviewLog, input: AnswerInput): void {
  const conflict = existing.word_id !== input.wordId
    || (existing.study_session_id ?? undefined) !== input.studySessionId
    || (existing.study_session_item_id ?? undefined) !== input.studySessionItemId;
  if (conflict) throw new Error("IDEMPOTENCY_KEY_CONFLICT");
}

export function buildIdempotentResult(existing: ExistingReviewLog) {
  const card = sqlite.prepare("SELECT due_at, scheduled_days FROM review_cards WHERE word_id = ?").get(existing.word_id) as {
    due_at: number;
    scheduled_days: number;
  } | undefined;
  const word = sqlite.prepare("SELECT mastery_score, mastery_level FROM words WHERE id = ?").get(existing.word_id) as {
    mastery_score: number;
    mastery_level: string;
  };
  const wrong = sqlite.prepare("SELECT active FROM wrong_word_states WHERE word_id = ?").get(existing.word_id) as {
    active: number;
  } | undefined;

  return {
    idempotent: true,
    reviewLogId: existing.id,
    isCorrect: Boolean(existing.is_correct),
    rating: existing.rating,
    expectedAnswer: existing.expected_answer ?? "",
    nextDueAt: card ? new Date(card.due_at).toISOString() : null,
    scheduledDays: card?.scheduled_days ?? 0,
    masteryScore: word.mastery_score,
    masteryLevel: word.mastery_level,
    wrongWordActive: Boolean(wrong?.active),
    adaptiveFollowUp: null,
  };
}

export function claimStudyItem(input: AnswerInput, now: number): void {
  const hasSessionId = input.studySessionId !== undefined;
  const hasItemId = input.studySessionItemId !== undefined;
  if (hasSessionId !== hasItemId || !hasSessionId || !hasItemId) throw new Error("INVALID_STUDY_CONTEXT");

  const item = sqlite.prepare(`SELECT i.word_id, i.question_type, i.status, s.completed_at
    FROM study_session_items i
    JOIN study_sessions s ON s.id = i.study_session_id
    WHERE i.id = ? AND i.study_session_id = ?`).get(input.studySessionItemId, input.studySessionId) as {
      word_id: number;
      question_type: string;
      status: string;
      completed_at: number | null;
    } | undefined;
  if (!item) throw new Error("STUDY_ITEM_NOT_FOUND");
  if (item.word_id !== input.wordId) throw new Error("STUDY_ITEM_WORD_MISMATCH");
  if (item.question_type !== input.questionType) throw new Error("STUDY_ITEM_QUESTION_MISMATCH");
  if (item.completed_at !== null || item.status !== "PENDING") throw new Error("STUDY_ITEM_ALREADY_PROCESSED");

  const claimed = sqlite.prepare(`UPDATE study_session_items SET status = 'ANSWERED', answered_at = ?
    WHERE id = ? AND study_session_id = ? AND status = 'PENDING'`)
    .run(now, input.studySessionItemId, input.studySessionId);
  if (claimed.changes !== 1) throw new Error("STUDY_ITEM_ALREADY_PROCESSED");
}

export function findReviewWord(wordId: number): ReviewWordRow | undefined {
  return sqlite.prepare(`SELECT w.id, w.term, w.normalized_term, w.source_language, w.target_language,
      w.content_type, w.initialization_status, w.is_suspended, c.definitions_json
    FROM words w LEFT JOIN word_contents c ON c.word_id = w.id WHERE w.id = ?`)
    .get(wordId) as ReviewWordRow | undefined;
}

export function assertReviewableWord(word: ReviewWordRow | undefined): asserts word is ReviewWordRow {
  if (!word) throw new Error("WORD_NOT_FOUND");
  if (!["READY", "PARTIAL"].includes(word.initialization_status)) throw new Error("WORD_NOT_READY");
  if (word.is_suspended) throw new Error("WORD_SUSPENDED");
}

export function findReviewCard(wordId: number): ReviewCardRow | undefined {
  return sqlite.prepare("SELECT * FROM review_cards WHERE word_id = ?").get(wordId) as ReviewCardRow | undefined;
}

export function saveReviewCard(wordId: number, card: Card, now: number): void {
  sqlite.prepare(`INSERT INTO review_cards
    (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses,
     fsrs_state, learning_steps, last_review_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(word_id) DO UPDATE SET due_at = excluded.due_at, stability = excluded.stability,
      difficulty = excluded.difficulty, elapsed_days = excluded.elapsed_days,
      scheduled_days = excluded.scheduled_days, reps = excluded.reps, lapses = excluded.lapses,
      fsrs_state = excluded.fsrs_state, learning_steps = excluded.learning_steps,
      last_review_at = excluded.last_review_at, updated_at = excluded.updated_at`)
    .run(
      wordId,
      card.due.getTime(),
      card.stability,
      card.difficulty,
      card.elapsed_days,
      card.scheduled_days,
      card.reps,
      card.lapses,
      card.state,
      card.learning_steps,
      now,
      now,
      now,
    );
}

export function insertReviewLog(input: {
  answer: AnswerInput;
  reviewedAt: number;
  rating: ReviewRating;
  presentedPrompt: string;
  expectedAnswer: string;
  isCorrect: boolean;
  before: Card;
  after: Card;
}): number {
  const result = sqlite.prepare(`INSERT INTO review_logs
    (client_answer_id, word_id, study_session_id, study_session_item_id, reviewed_at, rating,
     question_type, presented_prompt, user_answer, expected_answer, is_correct, duration_ms,
     card_before_json, card_after_json, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .run(
      input.answer.clientAnswerId,
      input.answer.wordId,
      input.answer.studySessionId ?? null,
      input.answer.studySessionItemId ?? null,
      input.reviewedAt,
      input.rating,
      input.answer.questionType,
      input.presentedPrompt,
      input.answer.userAnswer ?? null,
      input.expectedAnswer,
      input.isCorrect ? 1 : 0,
      boundedActiveDurationMs(input.answer.durationMs),
      JSON.stringify(input.before),
      JSON.stringify(input.after),
      input.reviewedAt,
    );
  return Number(result.lastInsertRowid);
}

function seedWordReviewStats(wordId: number, now: number): void {
  const seeded = sqlite.prepare(`SELECT
      count(*) AS total_reviews,
      sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct_reviews,
      sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_again_30d,
      sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_again_14d,
      sum(CASE WHEN is_correct = 0 AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_wrong_14d,
      sum(CASE WHEN rating = 'HARD' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_hard_14d,
      sum(CASE WHEN duration_ms IS NOT NULL AND duration_ms > 0 THEN duration_ms ELSE 0 END) AS total_duration_ms,
      sum(CASE WHEN duration_ms IS NOT NULL AND duration_ms > 0 THEN 1 ELSE 0 END) AS duration_count,
      max(reviewed_at) AS last_reviewed_at
    FROM review_logs WHERE word_id = ?`).get(now - MASTERY_WINDOW_MS, now - PERFORMANCE_WINDOW_MS, now - PERFORMANCE_WINDOW_MS, now - PERFORMANCE_WINDOW_MS, wordId) as {
      total_reviews: number | null;
      correct_reviews: number | null;
      recent_again_30d: number | null;
      recent_again_14d: number | null;
      recent_wrong_14d: number | null;
      recent_hard_14d: number | null;
      total_duration_ms: number | null;
      duration_count: number | null;
      last_reviewed_at: number | null;
    };
  sqlite.prepare(`INSERT INTO word_review_stats
    (word_id, total_reviews, correct_reviews, recent_again_30d, recent_again_14d,
     recent_wrong_14d, recent_hard_14d, total_duration_ms, duration_count,
     last_reviewed_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).run(
    wordId,
    seeded.total_reviews ?? 0,
    seeded.correct_reviews ?? 0,
    seeded.recent_again_30d ?? 0,
    seeded.recent_again_14d ?? 0,
    seeded.recent_wrong_14d ?? 0,
    seeded.recent_hard_14d ?? 0,
    seeded.total_duration_ms ?? 0,
    seeded.duration_count ?? 0,
    seeded.last_reviewed_at ?? now,
    now,
  );
}

/**
 * Keeps word_review_stats current. Lifetime counters are incremented, while the
 * 14/30 day window counters are recomputed for this word via the indexed
 * (word_id, reviewed_at) lookup, which is cheap because per-word history is small.
 * Must run inside the same transaction that inserted the review log.
 */
export function upsertWordReviewStats(input: {
  wordId: number;
  reviewedAt: number;
  rating: ReviewRating;
  isCorrect: boolean;
  durationMs: number | null;
}): void {
  const window30 = input.reviewedAt - MASTERY_WINDOW_MS;
  const window14 = input.reviewedAt - PERFORMANCE_WINDOW_MS;
  const windowed = sqlite.prepare(`SELECT
      SUM(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_again_30d,
      SUM(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_again_14d,
      SUM(CASE WHEN is_correct = 0 AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_wrong_14d,
      SUM(CASE WHEN rating = 'HARD' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_hard_14d,
      MAX(reviewed_at) AS last_reviewed_at
    FROM review_logs WHERE word_id = ?`).get(window30, window14, window14, window14, input.wordId) as {
      recent_again_30d: number | null;
      recent_again_14d: number | null;
      recent_wrong_14d: number | null;
      recent_hard_14d: number | null;
      last_reviewed_at: number | null;
    };
  const boundedDuration = input.durationMs != null && input.durationMs > 0 ? input.durationMs : 0;
  sqlite.prepare(`INSERT INTO word_review_stats
    (word_id, total_reviews, correct_reviews, recent_again_30d, recent_again_14d,
     recent_wrong_14d, recent_hard_14d, total_duration_ms, duration_count,
     last_reviewed_at, updated_at)
    VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(word_id) DO UPDATE SET
      total_reviews = total_reviews + 1,
      correct_reviews = correct_reviews + excluded.correct_reviews,
      recent_again_30d = excluded.recent_again_30d,
      recent_again_14d = excluded.recent_again_14d,
      recent_wrong_14d = excluded.recent_wrong_14d,
      recent_hard_14d = excluded.recent_hard_14d,
      total_duration_ms = total_duration_ms + excluded.total_duration_ms,
      duration_count = duration_count + excluded.duration_count,
      last_reviewed_at = excluded.last_reviewed_at,
      updated_at = excluded.updated_at`)
    .run(
      input.wordId,
      input.isCorrect ? 1 : 0,
      windowed.recent_again_30d ?? 0,
      windowed.recent_again_14d ?? 0,
      windowed.recent_wrong_14d ?? 0,
      windowed.recent_hard_14d ?? 0,
      boundedDuration,
      boundedDuration > 0 ? 1 : 0,
      windowed.last_reviewed_at ?? input.reviewedAt,
      input.reviewedAt,
    );
}

export function loadReviewStatistics(wordId: number, now: number): ReviewStatistics {
  const row = sqlite.prepare(`SELECT total_reviews, correct_reviews, recent_again_30d,
      total_duration_ms, duration_count
    FROM word_review_stats WHERE word_id = ?`).get(wordId) as {
      total_reviews: number;
      correct_reviews: number;
      recent_again_30d: number;
      total_duration_ms: number;
      duration_count: number;
    } | undefined;
  if (!row) {
    // Fallback for words that predate the materialized table (migration backfill
    // misses nothing, but this keeps the answer path robust regardless).
    const fallback = sqlite.prepare(`SELECT count(*) AS total,
      sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct,
      sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_again,
      avg(CASE WHEN duration_ms IS NOT NULL AND duration_ms > 0 THEN duration_ms ELSE NULL END) AS avg_duration
      FROM review_logs WHERE word_id = ?`)
      .get(now - MASTERY_WINDOW_MS, wordId) as ReviewStatistics;
    seedWordReviewStats(wordId, now);
    return fallback;
  }
  return {
    total: row.total_reviews,
    correct: row.correct_reviews,
    recent_again: row.recent_again_30d,
    avg_duration: row.duration_count > 0 ? row.total_duration_ms / row.duration_count : null,
  };
}

export function updateWordMastery(wordId: number, score: number, level: MasteryLevel, now: number): void {
  sqlite.prepare("UPDATE words SET mastery_score = ?, mastery_level = ?, updated_at = ? WHERE id = ?")
    .run(score, level, now, wordId);
}

export function finalizeStudySession(sessionId: number, isCorrect: boolean, now: number): void {
  sqlite.prepare(`UPDATE study_sessions SET completed_count = completed_count + 1,
    correct_count = correct_count + ?, wrong_count = wrong_count + ? WHERE id = ?`)
    .run(isCorrect ? 1 : 0, isCorrect ? 0 : 1, sessionId);
  const pending = sqlite.prepare("SELECT count(*) AS count FROM study_session_items WHERE study_session_id = ? AND status = 'PENDING'")
    .get(sessionId) as { count: number };
  if (pending.count > 0) return;

  closeStudySessionWithActiveDuration(sessionId, now);
}
