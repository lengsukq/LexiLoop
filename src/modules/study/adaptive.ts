import type { EntryType, QuestionType } from "@/lib/types";
import { sqlite } from "@/db/client";

const MAX_FOLLOW_UPS_PER_WORD = 2;
const FOLLOW_UP_DELAY = 3;
const POSITION_SHIFT = 1_000_000;

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
 * Put a failed word back into the current session after a short delay.
 * The follow-up is persisted as a normal session item so resume behavior stays reliable.
 */
export function scheduleAdaptiveFollowUp(input: {
  sessionId: number;
  itemId: number;
  wordId: number;
  currentQuestionType: QuestionType;
  entryType: EntryType;
  isCorrect: boolean;
  now?: number;
}): AdaptiveFollowUp | null {
  if (input.isCorrect) return null;

  const session = sqlite.prepare("SELECT completed_at, source_type FROM study_sessions WHERE id = ?")
    .get(input.sessionId) as { completed_at: number | null; source_type: string | null } | undefined;
  if (!session || session.completed_at !== null || isExcludedSession(session.source_type)) return null;

  const answeredCount = sqlite.prepare(`SELECT count(*) AS count
    FROM study_session_items WHERE study_session_id = ? AND word_id = ? AND status = 'ANSWERED'`)
    .get(input.sessionId, input.wordId) as { count: number };
  if (Number(answeredCount.count) >= MAX_FOLLOW_UPS_PER_WORD) return null;

  const current = sqlite.prepare(`SELECT position FROM study_session_items
    WHERE id = ? AND study_session_id = ?`)
    .get(input.itemId, input.sessionId) as { position: number } | undefined;
  if (!current) return null;

  const maxPosition = sqlite.prepare("SELECT COALESCE(MAX(position), -1) AS position FROM study_session_items WHERE study_session_id = ?")
    .get(input.sessionId) as { position: number };
  const position = Math.min(current.position + FOLLOW_UP_DELAY, Number(maxPosition.position) + 1);
  const questionType = nextQuestionType(input.currentQuestionType, input.entryType);
  const now = input.now ?? Date.now();

  sqlite.prepare(`UPDATE study_session_items SET position = position + ?
    WHERE study_session_id = ? AND position >= ?`).run(POSITION_SHIFT, input.sessionId, position);
  sqlite.prepare(`UPDATE study_session_items SET position = position - ?
    WHERE study_session_id = ? AND position >= ?`).run(POSITION_SHIFT - 1, input.sessionId, position + POSITION_SHIFT);
  sqlite.prepare(`INSERT INTO study_session_items
    (study_session_id, position, word_id, task_type, question_type, status, created_at)
    VALUES (?, ?, ?, 'WRONG', ?, 'PENDING', ?)`)
    .run(input.sessionId, position, input.wordId, questionType, now);
  sqlite.prepare("UPDATE study_sessions SET planned_count = planned_count + 1 WHERE id = ?")
    .run(input.sessionId);

  return {
    questionType,
    position,
    repetition: Number(answeredCount.count),
  };
}
