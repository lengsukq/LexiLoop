import type { EntryType, QuestionType, ReviewRating } from "@/lib/types";
import { sqlite } from "@/db/client";
import { DEFAULT_QUESTION_TYPE_CONFIG } from "@/lib/config";
import { getSettings } from "@/modules/settings/service";
import { normalizeQuestionTypeConfig, resolveAdaptiveQuestionType } from "./question-type-config";

const MAX_FOLLOW_UPS_PER_WORD = 2;
// 递增间隔检索：首次做错 5 题后快速复现（拯救工作记忆），二次做错 10 题后拉长间隔复现（加深长时记忆）
const FIRST_FOLLOW_UP_DELAY = 5;
const SECOND_FOLLOW_UP_DELAY = 10;

export interface AdaptiveFollowUp {
  questionType: QuestionType;
  position: number;
  repetition: number;
}

function nextQuestionType(current: QuestionType, entryType: EntryType): QuestionType {
  if (entryType === "SENTENCE") return "ZH_TO_EN_SPELLING";
  if (current === "EN_TO_ZH") return "EN_TO_ZH_CHOICE";
  if (current === "EN_TO_ZH_CHOICE") return "ZH_TO_EN_SPELLING";
  if (current === "ZH_TO_EN_CHOICE") return "ZH_TO_EN_SPELLING";
  if (current === "CLOZE_SENTENCE") return "ZH_TO_EN_SPELLING";
  if (current === "LISTENING_CHOICE") return "LISTENING_SPELLING";
  if (current === "LETTER_BANK") return "ZH_TO_EN_SPELLING";
  if (current === "LISTENING_SPELLING") return "LISTENING_CHOICE";
  return "ZH_TO_EN_SPELLING";
}

async function hasWordExample(wordId: number): Promise<boolean> {
  const row = await sqlite.prepare("SELECT examples_json FROM word_contents WHERE word_id = ?").get(wordId) as { examples_json: string | null } | undefined;
  if (!row?.examples_json) return false;
  try {
    const parsed = JSON.parse(row.examples_json) as unknown[];
    return Array.isArray(parsed) && parsed.some((item) => typeof (item as { sentence?: unknown }).sentence === "string" && String((item as { sentence: string }).sentence).trim().length > 0);
  } catch {
    return false;
  }
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

  const followUpDelay = Number(answeredCount.count) === 0 ? FIRST_FOLLOW_UP_DELAY : SECOND_FOLLOW_UP_DELAY;

  // Place the follow-up at least followUpDelay items after the current one.
  // We look up the followUpDelay-th item that follows the current item and
  // insert halfway between it and its predecessor. This keeps a real distance
  // (unlike the old midpoint-with-next hack) while avoiding an O(n) rewrite and
  // preserving the unique (study_session_id, position) constraint.
  const target = await sqlite.prepare(`SELECT position FROM study_session_items
    WHERE study_session_id = ? AND position > ?
    ORDER BY position ASC LIMIT 1 OFFSET ?`)
    .get(input.sessionId, current.position, followUpDelay - 1) as { position: number } | undefined;
  let position: number;
  if (target) {
    const prev = await sqlite.prepare(`SELECT position FROM study_session_items
      WHERE study_session_id = ? AND position < ?
      ORDER BY position DESC LIMIT 1`)
      .get(input.sessionId, target.position) as { position: number } | undefined;
    position = prev ? (prev.position + target.position) / 2 : current.position + followUpDelay;
  } else {
    // Fewer than followUpDelay items remain in the session: append to the end.
    const last = await sqlite.prepare(`SELECT MAX(position) AS position FROM study_session_items
      WHERE study_session_id = ?`).get(input.sessionId) as { position: number | null };
    position = (last?.position ?? current.position) + 1;
  }
  const settings = await getSettings();
  const questionTypeConfig = normalizeQuestionTypeConfig(settings.questionTypeConfig ?? DEFAULT_QUESTION_TYPE_CONFIG);
  const preferred = nextQuestionType(input.currentQuestionType, input.entryType);
  const wordRow = await sqlite.prepare("SELECT term FROM words WHERE id = ?").get(input.wordId) as { term: string } | undefined;
  const hasExample = await hasWordExample(input.wordId);
  const questionType = resolveAdaptiveQuestionType({
    preferred,
    entryType: input.entryType,
    extra: { term: wordRow?.term, hasExample },
    config: questionTypeConfig,
  });
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
