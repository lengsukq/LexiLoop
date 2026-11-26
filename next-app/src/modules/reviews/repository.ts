import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import type { MasteryLevel, ReviewRating } from "@/lib/types";
import type { Card } from "ts-fsrs";
import { DAY_MS } from "@/lib/time";
import type {
  AnswerInput,
  ExistingReviewLog,
  ReviewCardRow,
  ReviewStatistics,
  ReviewWordRow,
} from "./types";
import { boundedActiveDurationMs, MAX_ACTIVE_ANSWER_DURATION_MS } from "./duration";

const MASTERY_WINDOW_MS = 30 * DAY_MS;
const PERFORMANCE_WINDOW_MS = 14 * DAY_MS;

export async function findExistingReview(clientAnswerId: string): Promise<ExistingReviewLog | undefined> {
  return await sqlite.prepare(`SELECT id, word_id, study_session_id, study_session_item_id,
    rating, is_correct, expected_answer FROM review_logs WHERE client_answer_id = ?`)
    .get(clientAnswerId) as ExistingReviewLog | undefined;
}

export function assertIdempotencyContext(existing: ExistingReviewLog, input: AnswerInput): void {
  const conflict = existing.word_id !== input.wordId
    || (existing.study_session_id ?? undefined) !== input.studySessionId
    || (existing.study_session_item_id ?? undefined) !== input.studySessionItemId;
  if (conflict) throw new ApiError("IDEMPOTENCY_KEY_CONFLICT");
}

export async function buildIdempotentResult(existing: ExistingReviewLog) {
  const card = await sqlite.prepare("SELECT due_at, scheduled_days FROM review_cards WHERE word_id = ?").get(existing.word_id) as {
    due_at: number;
    scheduled_days: number;
  } | undefined;
  const word = await sqlite.prepare("SELECT mastery_score, mastery_level FROM words WHERE id = ?").get(existing.word_id) as {
    mastery_score: number;
    mastery_level: string;
  };
  const wrong = await sqlite.prepare("SELECT active FROM wrong_word_states WHERE word_id = ?").get(existing.word_id) as {
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

export async function claimStudyItem(input: AnswerInput, now: number): Promise<void> {
  const hasSessionId = input.studySessionId !== undefined;
  const hasItemId = input.studySessionItemId !== undefined;
  if (hasSessionId !== hasItemId || !hasSessionId || !hasItemId) throw new ApiError("INVALID_STUDY_CONTEXT");

  // Single statement claims the item: all validity checks are folded into the
  // WHERE clause so the common success path needs only one round trip.
  const claimed = await sqlite.prepare(`UPDATE study_session_items
    SET status = 'ANSWERED', answered_at = ?
    WHERE id = ? AND study_session_id = ?
      AND status = 'PENDING'
      AND word_id = ?
      AND question_type = ?
      AND EXISTS (SELECT 1 FROM study_sessions s WHERE s.id = ? AND s.completed_at IS NULL)`)
    .run(now, input.studySessionItemId, input.studySessionId, input.wordId, input.questionType, input.studySessionId);
  if (claimed.changes === 1) return;

  // Fall back to a diagnostic read to surface the specific conflict.
  const item = await sqlite.prepare(`SELECT i.word_id, i.question_type, i.status, s.completed_at
    FROM study_session_items i
    JOIN study_sessions s ON s.id = i.study_session_id
    WHERE i.id = ? AND i.study_session_id = ?`).get(input.studySessionItemId, input.studySessionId) as {
      word_id: number;
      question_type: string;
      status: string;
      completed_at: number | null;
    } | undefined;
  if (!item) throw new ApiError("STUDY_ITEM_NOT_FOUND");
  if (item.word_id !== input.wordId) throw new ApiError("STUDY_ITEM_WORD_MISMATCH");
  if (item.question_type !== input.questionType) throw new ApiError("STUDY_ITEM_QUESTION_MISMATCH");
  if (item.completed_at !== null || item.status !== "PENDING") throw new ApiError("STUDY_ITEM_ALREADY_PROCESSED");
}

export async function findReviewWord(wordId: number): Promise<ReviewWordRow | undefined> {
  return await sqlite.prepare(`SELECT w.id, w.term, w.normalized_term, w.source_language, w.target_language,
      w.content_type, w.initialization_status, w.is_suspended, c.definitions_json
    FROM words w LEFT JOIN word_contents c ON c.word_id = w.id WHERE w.id = ?`)
    .get(wordId) as ReviewWordRow | undefined;
}

export function assertReviewableWord(word: ReviewWordRow | undefined): asserts word is ReviewWordRow {
  if (!word) throw new ApiError("WORD_NOT_FOUND");
  if (!["READY", "PARTIAL"].includes(word.initialization_status)) throw new ApiError("WORD_NOT_READY");
  if (word.is_suspended) throw new ApiError("WORD_SUSPENDED");
}

export async function findReviewCard(wordId: number): Promise<ReviewCardRow | undefined> {
  return await sqlite.prepare("SELECT * FROM review_cards WHERE word_id = ?").get(wordId) as ReviewCardRow | undefined;
}

/** Loads the word, its review card and wrong-word state in a single round trip. */
export async function findReviewContext(wordId: number): Promise<{
  word: ReviewWordRow | undefined;
  card: ReviewCardRow | undefined;
  wrongState: import("./wrong-state").WrongStateRow | undefined;
}> {
  const row = await sqlite.prepare(`SELECT
      w.id, w.term, w.normalized_term, w.source_language, w.target_language,
      w.content_type, w.initialization_status, w.is_suspended, c.definitions_json,
      rc.due_at, rc.stability, rc.difficulty, rc.elapsed_days, rc.scheduled_days, rc.reps,
      rc.lapses, rc.fsrs_state, rc.last_review_at, rc.learning_steps,
      x.active AS wrong_active, x.wrong_count, x.hard_count, x.consecutive_correct,
      x.last_wrong_at, x.last_correct_at
    FROM words w
    LEFT JOIN word_contents c ON c.word_id = w.id
    LEFT JOIN review_cards rc ON rc.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id
    WHERE w.id = ?`).get(wordId) as Record<string, unknown> | undefined;
  if (!row) return { word: undefined, card: undefined, wrongState: undefined };

  const word: ReviewWordRow = {
    id: Number(row.id),
    term: String(row.term),
    normalized_term: String(row.normalized_term),
    source_language: String(row.source_language),
    target_language: String(row.target_language),
    content_type: String(row.content_type),
    initialization_status: String(row.initialization_status),
    is_suspended: Number(row.is_suspended),
    definitions_json: row.definitions_json === null ? null : String(row.definitions_json),
  };
  const card: ReviewCardRow | undefined = row.due_at === null ? undefined : {
    due_at: Number(row.due_at),
    stability: Number(row.stability),
    difficulty: Number(row.difficulty),
    elapsed_days: Number(row.elapsed_days),
    scheduled_days: Number(row.scheduled_days),
    reps: Number(row.reps),
    lapses: Number(row.lapses),
    fsrs_state: Number(row.fsrs_state),
    last_review_at: row.last_review_at === null ? null : Number(row.last_review_at),
    learning_steps: Number(row.learning_steps ?? 0),
  };
  const wrongState: import("./wrong-state").WrongStateRow | undefined = row.wrong_active === null ? undefined : {
    active: Number(row.wrong_active),
    wrong_count: Number(row.wrong_count),
    hard_count: Number(row.hard_count),
    consecutive_correct: Number(row.consecutive_correct),
    last_wrong_at: row.last_wrong_at === null ? null : Number(row.last_wrong_at),
    last_correct_at: row.last_correct_at === null ? null : Number(row.last_correct_at),
  };
  return { word, card, wrongState };
}

export async function saveReviewCard(wordId: number, card: Card, now: number): Promise<void> {
  await sqlite.prepare(`INSERT INTO review_cards
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

export async function insertReviewLog(input: {
  answer: AnswerInput;
  reviewedAt: number;
  rating: ReviewRating;
  presentedPrompt: string;
  expectedAnswer: string;
  isCorrect: boolean;
  before: Card;
  after: Card;
}): Promise<number> {
  const result = await sqlite.prepare(`INSERT INTO review_logs
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

/** Persists the review card and the review log in a single round trip. */
export async function insertReviewCardAndLog(input: {
  answer: AnswerInput;
  reviewedAt: number;
  rating: ReviewRating;
  presentedPrompt: string;
  expectedAnswer: string;
  isCorrect: boolean;
  before: Card;
  after: Card;
  now: number;
}): Promise<number> {
  const card = input.after;
  const row = await sqlite.prepare(`WITH card AS (
      INSERT INTO review_cards
        (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses,
         fsrs_state, learning_steps, last_review_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(word_id) DO UPDATE SET due_at = excluded.due_at, stability = excluded.stability,
          difficulty = excluded.difficulty, elapsed_days = excluded.elapsed_days,
          scheduled_days = excluded.scheduled_days, reps = excluded.reps, lapses = excluded.lapses,
          fsrs_state = excluded.fsrs_state, learning_steps = excluded.learning_steps,
          last_review_at = excluded.last_review_at, updated_at = excluded.updated_at
        RETURNING word_id
    ),
    log AS (
      INSERT INTO review_logs
        (client_answer_id, word_id, study_session_id, study_session_item_id, reviewed_at, rating,
         question_type, presented_prompt, user_answer, expected_answer, is_correct, duration_ms,
         card_before_json, card_after_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        RETURNING id
    )
    SELECT log.id FROM log, card`).get(
      input.answer.wordId,
      card.due.getTime(),
      card.stability,
      card.difficulty,
      card.elapsed_days,
      card.scheduled_days,
      card.reps,
      card.lapses,
      card.state,
      card.learning_steps,
      input.now,
      input.now,
      input.now,
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
    ) as { id: number } | undefined;
  return Number(row?.id);
}

async function seedWordReviewStats(wordId: number, now: number): Promise<void> {
  const seeded = await sqlite.prepare(`SELECT
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
  await sqlite.prepare(`INSERT INTO word_review_stats
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
 * The windowed reads are folded into scalar subqueries so the whole update is a
 * single round trip, and RETURNING supplies the refreshed statistics directly.
 * Must run inside the same transaction that inserted the review log.
 */
export async function upsertWordReviewStats(input: {
  wordId: number;
  reviewedAt: number;
  rating: ReviewRating;
  isCorrect: boolean;
  durationMs: number | null;
}): Promise<ReviewStatistics> {
  const window30 = input.reviewedAt - MASTERY_WINDOW_MS;
  const window14 = input.reviewedAt - PERFORMANCE_WINDOW_MS;
  const boundedDuration = input.durationMs != null && input.durationMs > 0 ? input.durationMs : 0;
  const row = await sqlite.prepare(`INSERT INTO word_review_stats
    (word_id, total_reviews, correct_reviews, recent_again_30d, recent_again_14d,
     recent_wrong_14d, recent_hard_14d, total_duration_ms, duration_count,
     last_reviewed_at, updated_at)
    VALUES (?, 1, ?,
      (SELECT COALESCE(SUM(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0) FROM review_logs WHERE word_id = ?),
      (SELECT COALESCE(SUM(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0) FROM review_logs WHERE word_id = ?),
      (SELECT COALESCE(SUM(CASE WHEN is_correct = 0 AND reviewed_at >= ? THEN 1 ELSE 0 END), 0) FROM review_logs WHERE word_id = ?),
      (SELECT COALESCE(SUM(CASE WHEN rating = 'HARD' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0) FROM review_logs WHERE word_id = ?),
      ?, ?,
      (SELECT COALESCE(MAX(reviewed_at), ?) FROM review_logs WHERE word_id = ?),
      ?)
    ON CONFLICT(word_id) DO UPDATE SET
      total_reviews = word_review_stats.total_reviews + 1,
      correct_reviews = word_review_stats.correct_reviews + excluded.correct_reviews,
      recent_again_30d = excluded.recent_again_30d,
      recent_again_14d = excluded.recent_again_14d,
      recent_wrong_14d = excluded.recent_wrong_14d,
      recent_hard_14d = excluded.recent_hard_14d,
      total_duration_ms = word_review_stats.total_duration_ms + excluded.total_duration_ms,
      duration_count = word_review_stats.duration_count + excluded.duration_count,
      last_reviewed_at = excluded.last_reviewed_at,
      updated_at = excluded.updated_at
    RETURNING total_reviews, correct_reviews, recent_again_30d, total_duration_ms, duration_count`)
    .get(
      input.wordId,
      input.isCorrect ? 1 : 0,
      window30, input.wordId,
      window14, input.wordId,
      window14, input.wordId,
      window14, input.wordId,
      boundedDuration,
      boundedDuration > 0 ? 1 : 0,
      input.reviewedAt, input.wordId,
      input.reviewedAt,
    ) as {
      total_reviews: number;
      correct_reviews: number;
      recent_again_30d: number;
      total_duration_ms: number;
      duration_count: number;
    } | undefined;
  const total = Number(row?.total_reviews ?? 0);
  const correct = Number(row?.correct_reviews ?? 0);
  const durationCount = Number(row?.duration_count ?? 0);
  return {
    total,
    correct,
    recent_again: Number(row?.recent_again_30d ?? 0),
    avg_duration: durationCount > 0 ? Number(row?.total_duration_ms ?? 0) / durationCount : null,
  };
}

export async function loadReviewStatistics(wordId: number, now: number): Promise<ReviewStatistics> {
  const row = await sqlite.prepare(`SELECT total_reviews, correct_reviews, recent_again_30d,
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
    const fallback = await sqlite.prepare(`SELECT count(*) AS total,
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

export async function updateWordMastery(wordId: number, score: number, level: MasteryLevel, now: number): Promise<void> {
  await sqlite.prepare("UPDATE words SET mastery_score = ?, mastery_level = ?, updated_at = ? WHERE id = ?")
    .run(score, level, now, wordId);
}

/** Updates word mastery and finalizes the study session in a single round trip. */
export async function applyMasteryAndFinalize(
  wordId: number,
  score: number,
  level: MasteryLevel,
  now: number,
  sessionId: number,
  isCorrect: boolean,
): Promise<void> {
  const hasPending = `(SELECT count(*) FROM study_session_items WHERE study_session_id = ? AND status = 'PENDING')`;
  await sqlite.prepare(`WITH master AS (
      UPDATE words SET mastery_score = ?, mastery_level = ?, updated_at = ? WHERE id = ?
      RETURNING id
    ),
    finalize AS (
      UPDATE study_sessions SET
        completed_count = completed_count + ?,
        correct_count = correct_count + ?,
        wrong_count = wrong_count + ?,
        completed_at = COALESCE(completed_at, CASE WHEN ${hasPending} = 0 THEN CAST(? AS BIGINT) END),
        duration_ms = CASE WHEN ${hasPending} = 0
          THEN (SELECT COALESCE(SUM(CASE WHEN duration_ms IS NULL OR duration_ms <= 0 THEN 0 WHEN duration_ms > CAST(? AS BIGINT) THEN CAST(? AS BIGINT) ELSE duration_ms END), 0) FROM review_logs WHERE study_session_id = ?)
          ELSE duration_ms END
        WHERE id = ?
        RETURNING id
    )
    SELECT 1`).run(
      score,
      level,
      now,
      wordId,
      isCorrect ? 1 : 0,
      isCorrect ? 1 : 0,
      isCorrect ? 0 : 1,
      sessionId,
      now,
      sessionId,
      MAX_ACTIVE_ANSWER_DURATION_MS,
      MAX_ACTIVE_ANSWER_DURATION_MS,
      sessionId,
      sessionId,
    );
}

export async function finalizeStudySession(sessionId: number, isCorrect: boolean, now: number): Promise<void> {
  // Single statement: bump the counters, and when no PENDING item remains also
  // stamp the session as completed and backfill its active duration.
  const hasPending = `(SELECT count(*) FROM study_session_items WHERE study_session_id = ? AND status = 'PENDING')`;
  await sqlite.prepare(`UPDATE study_sessions SET
    completed_count = completed_count + ?,
    correct_count = correct_count + ?,
    wrong_count = wrong_count + ?,
    completed_at = COALESCE(completed_at, CASE WHEN ${hasPending} = 0 THEN CAST(? AS BIGINT) END),
    duration_ms = CASE WHEN ${hasPending} = 0
      THEN (SELECT COALESCE(SUM(CASE WHEN duration_ms IS NULL OR duration_ms <= 0 THEN 0 WHEN duration_ms > CAST(? AS BIGINT) THEN CAST(? AS BIGINT) ELSE duration_ms END), 0) FROM review_logs WHERE study_session_id = ?)
      ELSE duration_ms END
    WHERE id = ?`)
    .run(
      isCorrect ? 1 : 0,
      isCorrect ? 1 : 0,
      isCorrect ? 0 : 1,
      sessionId,
      now,
      sessionId,
      MAX_ACTIVE_ANSWER_DURATION_MS,
      MAX_ACTIVE_ANSWER_DURATION_MS,
      sessionId,
      sessionId,
    );
}
