import { sqlite } from "@/db/client";
import type { QuestionType, ReviewRating } from "@/lib/types";
import { getSettings } from "@/modules/settings/service";
import { normalizeTerm } from "@/modules/imports/normalizer";
import { calculateMasteryScore, determineMasteryLevel } from "./mastery";
import { cardFromRow, emptyCard, previewCard, scheduleCard } from "./fsrs";
import type { Card } from "ts-fsrs";

interface AnswerInput {
  clientAnswerId: string;
  wordId: number;
  studySessionId?: number;
  studySessionItemId?: number;
  rating: ReviewRating;
  questionType: QuestionType;
  userAnswer?: string;
  durationMs?: number;
}

interface ExistingReviewLog {
  id: number;
  word_id: number;
  study_session_id: number | null;
  study_session_item_id: number | null;
  rating: ReviewRating;
  is_correct: number;
  expected_answer: string | null;
}

const appTimezone = process.env.APP_TIMEZONE ?? "Asia/Shanghai";
function localDayOrdinal(timestamp: number): number {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: appTimezone,
    year: "numeric",
    month: "numeric",
    day: "numeric",
  }).formatToParts(new Date(timestamp));
  const values = Object.fromEntries(parts.map((part) => [part.type, Number(part.value)]));
  return Math.floor(Date.UTC(values.year!, values.month! - 1, values.day!) / 86_400_000);
}

function upsertWrongState(wordId: number, rating: ReviewRating, isCorrect: boolean, now: number): { active: boolean; consecutiveCorrect: number } {
  const current = sqlite.prepare("SELECT * FROM wrong_word_states WHERE word_id = ?").get(wordId) as {
    active: number; wrong_count: number; hard_count: number; consecutive_correct: number; last_wrong_at: number | null; last_correct_at: number | null;
  } | undefined;
  if (!isCorrect || rating === "AGAIN") {
    sqlite.prepare(`INSERT INTO wrong_word_states(word_id, active, wrong_count, hard_count, consecutive_correct, last_wrong_at, updated_at)
      VALUES (?, 1, 1, 0, 0, ?, ?)
      ON CONFLICT(word_id) DO UPDATE SET active = 1, wrong_count = wrong_count + 1,
        consecutive_correct = 0, last_wrong_at = excluded.last_wrong_at, resolved_at = NULL, updated_at = excluded.updated_at`)
      .run(wordId, now, now);
    return { active: true, consecutiveCorrect: 0 };
  }
  if (rating === "HARD") {
    sqlite.prepare(`INSERT INTO wrong_word_states(word_id, active, wrong_count, hard_count, consecutive_correct, updated_at)
      VALUES (?, 1, 0, 1, 0, ?)
      ON CONFLICT(word_id) DO UPDATE SET active = 1, hard_count = hard_count + 1,
        consecutive_correct = 0, resolved_at = NULL, updated_at = excluded.updated_at`)
      .run(wordId, now);
    return { active: true, consecutiveCorrect: 0 };
  }
  if (!current) return { active: false, consecutiveCorrect: 1 };
  const previousDay = current.last_correct_at ? localDayOrdinal(current.last_correct_at) : null;
  const currentDay = localDayOrdinal(now);
  const dayGap = previousDay === null ? null : currentDay - previousDay;
  const consecutive = dayGap === 0
    ? current.consecutive_correct
    : dayGap === 1
      ? current.consecutive_correct + 1
      : 1;
  const oldEnough = current.last_wrong_at === null || currentDay - localDayOrdinal(current.last_wrong_at) >= 2;
  const resolved = consecutive >= 3 && oldEnough;
  sqlite.prepare(`UPDATE wrong_word_states SET consecutive_correct = ?, last_correct_at = ?, active = ?,
    resolved_at = ?, updated_at = ? WHERE word_id = ?`)
    .run(consecutive, now, resolved ? 0 : current.active, resolved ? now : null, now, wordId);
  return { active: resolved ? false : Boolean(current.active), consecutiveCorrect: consecutive };
}

function validateIdempotencyContext(existing: ExistingReviewLog, input: AnswerInput): void {
  if (existing.word_id !== input.wordId) throw new Error("IDEMPOTENCY_KEY_CONFLICT");
  if ((existing.study_session_id ?? undefined) !== input.studySessionId) throw new Error("IDEMPOTENCY_KEY_CONFLICT");
  if ((existing.study_session_item_id ?? undefined) !== input.studySessionItemId) throw new Error("IDEMPOTENCY_KEY_CONFLICT");
}

function buildIdempotentResult(existing: ExistingReviewLog) {
  const card = sqlite.prepare("SELECT due_at, scheduled_days FROM review_cards WHERE word_id = ?").get(existing.word_id) as {
    due_at: number; scheduled_days: number;
  } | undefined;
  const word = sqlite.prepare("SELECT mastery_score, mastery_level FROM words WHERE id = ?").get(existing.word_id) as {
    mastery_score: number; mastery_level: string;
  };
  const wrong = sqlite.prepare("SELECT active FROM wrong_word_states WHERE word_id = ?").get(existing.word_id) as { active: number } | undefined;
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

function validateAndClaimStudyItem(input: AnswerInput, now: number): boolean {
  const hasSessionId = input.studySessionId !== undefined;
  const hasItemId = input.studySessionItemId !== undefined;
  if (hasSessionId !== hasItemId || !hasSessionId || !hasItemId) throw new Error("INVALID_STUDY_CONTEXT");

  const item = sqlite.prepare(`SELECT i.word_id, i.question_type, i.status, s.completed_at
    FROM study_session_items i JOIN study_sessions s ON s.id = i.study_session_id
    WHERE i.id = ? AND i.study_session_id = ?`).get(input.studySessionItemId, input.studySessionId) as {
      word_id: number; question_type: string; status: string; completed_at: number | null;
    } | undefined;
  if (!item) throw new Error("STUDY_ITEM_NOT_FOUND");
  if (item.word_id !== input.wordId) throw new Error("STUDY_ITEM_WORD_MISMATCH");
  if (item.question_type !== input.questionType) throw new Error("STUDY_ITEM_QUESTION_MISMATCH");
  if (item.completed_at !== null || item.status !== "PENDING") throw new Error("STUDY_ITEM_ALREADY_PROCESSED");

  const claimed = sqlite.prepare(`UPDATE study_session_items
    SET status = 'ANSWERED', answered_at = ?
    WHERE id = ? AND study_session_id = ? AND status = 'PENDING'`)
    .run(now, input.studySessionItemId, input.studySessionId);
  if (claimed.changes !== 1) throw new Error("STUDY_ITEM_ALREADY_PROCESSED");
  return true;
}

function finalizeClaimedSessionItem(sessionId: number, isCorrect: boolean, now: number): void {
  sqlite.prepare(`UPDATE study_sessions SET completed_count = completed_count + 1,
    correct_count = correct_count + ?, wrong_count = wrong_count + ? WHERE id = ?`)
    .run(isCorrect ? 1 : 0, isCorrect ? 0 : 1, sessionId);
  const pending = sqlite.prepare("SELECT count(*) AS count FROM study_session_items WHERE study_session_id = ? AND status = 'PENDING'").get(sessionId) as { count: number };
  if (pending.count === 0) {
    const session = sqlite.prepare("SELECT started_at FROM study_sessions WHERE id = ?").get(sessionId) as { started_at: number };
    sqlite.prepare("UPDATE study_sessions SET completed_at = ?, duration_ms = ? WHERE id = ?")
      .run(now, now - session.started_at, sessionId);
  }
}

export async function processReviewAnswer(input: AnswerInput) {
  const settings = await getSettings();
  const transaction = sqlite.transaction(() => {
    const existingLog = sqlite.prepare(`SELECT id, word_id, study_session_id, study_session_item_id,
      rating, is_correct, expected_answer FROM review_logs WHERE client_answer_id = ?`)
      .get(input.clientAnswerId) as ExistingReviewLog | undefined;
    if (existingLog) {
      validateIdempotencyContext(existingLog, input);
      return buildIdempotentResult(existingLog);
    }

    const nowDate = new Date();
    const now = nowDate.getTime();
    const claimedSessionItem = validateAndClaimStudyItem(input, now);

    const word = sqlite.prepare("SELECT * FROM words WHERE id = ?").get(input.wordId) as {
      id: number; term: string; normalized_term: string; source_language: string; target_language: string;
      initialization_status: string; is_suspended: number;
    } | undefined;
    if (!word) throw new Error("WORD_NOT_FOUND");
    if (!["READY", "PARTIAL"].includes(word.initialization_status)) throw new Error("WORD_NOT_READY");
    if (word.is_suspended) throw new Error("WORD_SUSPENDED");

    const spelling = input.questionType === "ZH_TO_EN_SPELLING" || input.questionType === "LISTENING_SPELLING";
    const isChoice = input.questionType === "EN_TO_ZH_CHOICE";
    const normalizedAnswer = normalizeTerm(input.userAnswer ?? "", word.source_language);
    let isCorrect: boolean;
    if (spelling) {
      isCorrect = normalizedAnswer === word.normalized_term;
    } else if (isChoice) {
      const content = sqlite.prepare("SELECT definitions_json FROM word_contents WHERE word_id = ?").get(word.id) as { definitions_json: string } | undefined;
      if (content) {
        try {
          const defs = JSON.parse(content.definitions_json) as Array<{ language: string; text: string }>;
          const target = defs.filter((d) => d.language === word.target_language);
          const correctDef = (target.length ? target : defs)[0]?.text ?? "";
          isCorrect = (input.userAnswer ?? "").trim() === correctDef.trim();
        } catch { isCorrect = input.rating !== "AGAIN"; }
      } else { isCorrect = input.rating !== "AGAIN"; }
    } else {
      isCorrect = input.rating !== "AGAIN";
    }
    const effectiveRating: ReviewRating = (spelling || isChoice) && !isCorrect ? "AGAIN" : input.rating;
    const currentRow = sqlite.prepare("SELECT * FROM review_cards WHERE word_id = ?").get(word.id) as {
      due_at: number; stability: number; difficulty: number; elapsed_days: number; scheduled_days: number;
      reps: number; lapses: number; fsrs_state: number; learning_steps: number; last_review_at: number | null;
    } | undefined;
    const before: Card = currentRow ? cardFromRow(currentRow) : emptyCard(nowDate);
    const scheduled = scheduleCard(before, nowDate, effectiveRating, settings.targetRetentionRate);
    const next = scheduled.card;

    sqlite.prepare(`INSERT INTO review_cards
      (word_id, due_at, stability, difficulty, elapsed_days, scheduled_days, reps, lapses, fsrs_state, learning_steps, last_review_at, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(word_id) DO UPDATE SET due_at = excluded.due_at, stability = excluded.stability,
        difficulty = excluded.difficulty, elapsed_days = excluded.elapsed_days, scheduled_days = excluded.scheduled_days,
        reps = excluded.reps, lapses = excluded.lapses, fsrs_state = excluded.fsrs_state, learning_steps = excluded.learning_steps,
        last_review_at = excluded.last_review_at, updated_at = excluded.updated_at`)
      .run(word.id, next.due.getTime(), next.stability, next.difficulty, next.elapsed_days, next.scheduled_days,
        next.reps, next.lapses, next.state, next.learning_steps, now, now, now);

    const expected = (input.questionType === "EN_TO_ZH" || isChoice) ? (() => {
      const content = sqlite.prepare("SELECT definitions_json FROM word_contents WHERE word_id = ?").get(word.id) as { definitions_json: string } | undefined;
      if (!content) return "";
      try {
        const values = JSON.parse(content.definitions_json) as Array<{ language: string; text: string }>;
        const target = values.filter((item) => item.language === word.target_language);
        return (target.length ? target : values).map((item) => item.text).join("；");
      } catch { return ""; }
    })() : word.term;
    const prompt = (input.questionType === "EN_TO_ZH" || isChoice) ? word.term : expected;
    const log = sqlite.prepare(`INSERT INTO review_logs
      (client_answer_id, word_id, study_session_id, study_session_item_id, reviewed_at, rating, question_type,
       presented_prompt, user_answer, expected_answer, is_correct, duration_ms, card_before_json, card_after_json, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .run(input.clientAnswerId, word.id, input.studySessionId ?? null, input.studySessionItemId ?? null,
        now, effectiveRating, input.questionType, prompt, input.userAnswer ?? null, expected,
        isCorrect ? 1 : 0, input.durationMs ?? null, JSON.stringify(before), JSON.stringify(next), now);

    const wrong = upsertWrongState(word.id, effectiveRating, isCorrect, now);
    const stats = sqlite.prepare(`SELECT count(*) AS total,
      sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct,
      sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END) AS recent_again,
      avg(CASE WHEN duration_ms IS NOT NULL AND duration_ms > 0 THEN duration_ms ELSE NULL END) AS avg_duration
      FROM review_logs WHERE word_id = ?`).get(now - 30 * 24 * 60 * 60 * 1000, word.id) as { total: number; correct: number; recent_again: number; avg_duration: number | null };
    const masteryInput = {
      stability: next.stability,
      scheduledDays: next.scheduled_days,
      reps: next.reps,
      lapses: next.lapses,
      accuracy: stats.total ? stats.correct / stats.total : 0,
      consecutiveCorrect: wrong.consecutiveCorrect,
      activeWrongWord: wrong.active,
      recentAgain: stats.recent_again ?? 0,
      avgDurationMs: stats.avg_duration ?? undefined,
    };
    const masteryScore = calculateMasteryScore(masteryInput);
    const masteryLevel = determineMasteryLevel(masteryInput, masteryScore);
    sqlite.prepare("UPDATE words SET mastery_score = ?, mastery_level = ?, updated_at = ? WHERE id = ?")
      .run(masteryScore, masteryLevel, now, word.id);
    if (claimedSessionItem && input.studySessionId) finalizeClaimedSessionItem(input.studySessionId, isCorrect, now);

    return {
      idempotent: false,
      reviewLogId: Number(log.lastInsertRowid),
      isCorrect,
      rating: effectiveRating,
      expectedAnswer: expected,
      nextDueAt: next.due.toISOString(),
      scheduledDays: next.scheduled_days,
      masteryScore,
      masteryLevel,
      wrongWordActive: wrong.active,
    };
  });
  return transaction.immediate();
}

export async function getReviewPreview(wordId: number) {
  const settings = await getSettings();
  const row = sqlite.prepare("SELECT * FROM review_cards WHERE word_id = ?").get(wordId) as {
    due_at: number; stability: number; difficulty: number; elapsed_days: number; scheduled_days: number;
    reps: number; lapses: number; fsrs_state: number; learning_steps: number; last_review_at: number | null;
  } | undefined;
  const card = row ? cardFromRow(row) : emptyCard(new Date());
  return previewCard(card, new Date(), settings.targetRetentionRate).map((item) => ({
    ...item,
    nextDueAt: item.nextDueAt.toISOString(),
  }));
}
