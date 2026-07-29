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

export function loadReviewStatistics(wordId: number, now: number): ReviewStatistics {
  return sqlite.prepare(`SELECT count(*) AS total,
    sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct,
    sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_again,
    avg(CASE WHEN duration_ms IS NOT NULL AND duration_ms > 0 THEN duration_ms ELSE NULL END) AS avg_duration
    FROM review_logs WHERE word_id = ?`)
    .get(now - MASTERY_WINDOW_MS, wordId) as ReviewStatistics;
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
