import type { EntryType, QuestionType, ReviewRating } from "@/lib/types";
import { sqlite } from "@/db/client";

const MAX_FOLLOW_UPS_PER_WORD = 2;
// The follow-up should only reappear well after the current question, so that
// the learner gets a chance to answer several other items in between.
const FOLLOW_UP_DELAY = 8;

export interface AdaptiveFollowUp {
  questionType: QuestionType;
  position: number;
  repetition: number;
}

function nextQuestionType(current: QuestionType, entryType: EntryType): QuestionType {
  if (entryType === "SENTENCE") return "ZH_TO_EN_SPELLING";
  return current === "EN_TO_ZH_CHOICE" ? "ZH_TO_EN_SPELLING" : "EN_TO_ZH_CHOICE";
}

function isExcludedSession(sourceType: string | null): boolean {
  return sourceType === "MATCH_GAME" || Boolean(sourceType?.startsWith("GAME_"));
}

/**
 * Put a forgotten word back into the current session after a delay.
 *
 * Only full lapses (AGAIN) get an in-session follow-up. Fuzzy (HARD) words are
 * intentionally not re-inserted here: they already entered the wrong-word pool
 * and will be picked up by a future session. The follow-up is persisted as a
 * normal session item so resume behavior stays reliable.
 */
export async function scheduleAdaptiveFollowUp(input: {
  sessionId: number;
  itemId: number;
  wordId: number;
  currentQuestionType: QuestionType;
  entryType: EntryType;
  isCorrect: boolean;
  rating: ReviewRating;
  now?: number;
}): Promise<AdaptiveFollowUp | null> {
  if (input.isCorrect || input.rating === "HARD") return null;

  const session = await sqlite.prepare("SELECT completed_at, source_type FROM study_sessions WHERE id = ?")
    .get(input.sessionId) as { completed_at: number | null; source_type: string | null } | undefined;
  if (!session || session.completed_at !== null || isExcludedSession(session.source_type)) return null;

  const answeredCount = await sqlite.prepare(`SELECT count(*) AS count
    FROM study_session_items WHERE study_session_id = ? AND word_id = ? AND status = 'ANSWERED'`)
    .get(input.sessionId, input.wordId) as { count: number };
  if (Number(answeredCount.count) >= MAX_FOLLOW_UPS_PER_WORD) return null;

  // If this word already has an unanswered item in the queue (e.g. a previous
  // follow-up that was not answered yet), do not stack another one.
  const pendingCount = await sqlite.prepare(`SELECT count(*) AS count
    FROM study_session_items WHERE study_session_id = ? AND word_id = ? AND status = 'PENDING'`)
    .get(input.sessionId, input.wordId) as { count: number };
  if (Number(pendingCount.count) > 0) return null;

  const current = await sqlite.prepare(`SELECT position FROM study_session_items
    WHERE id = ? AND study_session_id = ?`)
    .get(input.itemId, input.sessionId) as { position: number } | undefined;
  if (!current) return null;

  // Place the follow-up at least FOLLOW_UP_DELAY items after the current one.
  // We look up the FOLLOW_UP_DELAY-th item that follows the current item and
  // insert halfway between it and its predecessor. This keeps a real distance
  // (unlike the old midpoint-with-next hack) while avoiding an O(n) rewrite and
  // preserving the unique (study_session_id, position) constraint.
  const target = await sqlite.prepare(`SELECT position FROM study_session_items
    WHERE study_session_id = ? AND position > ?
    ORDER BY position ASC LIMIT 1 OFFSET ?`)
    .get(input.sessionId, current.position, FOLLOW_UP_DELAY - 1) as { position: number } | undefined;
  let position: number;
  if (target) {
    const prev = await sqlite.prepare(`SELECT position FROM study_session_items
      WHERE study_session_id = ? AND position < ?
      ORDER BY position DESC LIMIT 1`)
      .get(input.sessionId, target.position) as { position: number } | undefined;
    position = prev ? (prev.position + target.position) / 2 : current.position + FOLLOW_UP_DELAY;
  } else {
    // Fewer than FOLLOW_UP_DELAY items remain in the session: append to the end.
    const last = await sqlite.prepare(`SELECT MAX(position) AS position FROM study_session_items
      WHERE study_session_id = ?`).get(input.sessionId) as { position: number | null };
    position = (last?.position ?? current.position) + 1;
  }
  const questionType = nextQuestionType(input.currentQuestionType, input.entryType);
  const now = input.now ?? Date.now();

  await sqlite.prepare(`INSERT INTO study_session_items
    (study_session_id, position, word_id, task_type, question_type, status, created_at)
    VALUES (?, ?, ?, 'WRONG', ?, 'PENDING', ?)`)
    .run(input.sessionId, position, input.wordId, questionType, now);
  await sqlite.prepare("UPDATE study_sessions SET planned_count = planned_count + 1 WHERE id = ?")
    .run(input.sessionId);

  return {
    questionType,
    position,
    repetition: Number(answeredCount.count),
  };
}
