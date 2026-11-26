import { sqlite } from "@/db/client";
import type { ReviewRating } from "@/lib/types";
import type { WrongStateResult } from "./types";
import { localDayOrdinal } from "@/lib/date-key";

export interface WrongStateRow {
  active: number;
  wrong_count: number;
  hard_count: number;
  consecutive_correct: number;
  last_wrong_at: number | null;
  last_correct_at: number | null;
}

async function recordWrong(wordId: number, now: number): Promise<WrongStateResult> {
  await sqlite.prepare(`INSERT INTO wrong_word_states(word_id, active, wrong_count, hard_count, consecutive_correct, last_wrong_at, updated_at)
    VALUES (?, 1, 1, 0, 0, ?, ?)
    ON CONFLICT(word_id) DO UPDATE SET active = 1, wrong_count = wrong_word_states.wrong_count + 1,
      consecutive_correct = 0, last_wrong_at = excluded.last_wrong_at, resolved_at = NULL, updated_at = excluded.updated_at`)
    .run(wordId, now, now);
  return { active: true, consecutiveCorrect: 0 };
}

async function recordHard(wordId: number, now: number): Promise<WrongStateResult> {
  await sqlite.prepare(`INSERT INTO wrong_word_states(word_id, active, wrong_count, hard_count, consecutive_correct, updated_at)
    VALUES (?, 1, 0, 1, 0, ?)
    ON CONFLICT(word_id) DO UPDATE SET active = 1, hard_count = wrong_word_states.hard_count + 1,
      consecutive_correct = 0, resolved_at = NULL, updated_at = excluded.updated_at`)
    .run(wordId, now);
  return { active: true, consecutiveCorrect: 0 };
}

function nextConsecutiveCorrect(current: WrongStateRow, now: number): number {
  const previousDay = current.last_correct_at ? localDayOrdinal(current.last_correct_at) : null;
  const dayGap = previousDay === null ? null : localDayOrdinal(now) - previousDay;
  if (dayGap === 0) return current.consecutive_correct;
  if (dayGap === 1) return current.consecutive_correct + 1;
  return 1;
}

export async function updateWrongWordState(
  wordId: number,
  rating: ReviewRating,
  isCorrect: boolean,
  now: number,
  current?: WrongStateRow,
): Promise<WrongStateResult> {
  if (current === undefined) {
    current = await sqlite.prepare("SELECT * FROM wrong_word_states WHERE word_id = ?").get(wordId) as WrongStateRow | undefined;
  }
  if (rating === "EASY") {
    if (!current) return { active: false, consecutiveCorrect: 1 };
    await sqlite.prepare(`UPDATE wrong_word_states SET consecutive_correct = 1, last_correct_at = ?, active = 0,
      resolved_at = ?, updated_at = ? WHERE word_id = ?`).run(now, now, now, wordId);
    return { active: false, consecutiveCorrect: 1 };
  }
  if (!isCorrect || rating === "AGAIN") return recordWrong(wordId, now);
  if (rating === "HARD") return recordHard(wordId, now);
  if (!current) return { active: false, consecutiveCorrect: 1 };

  const consecutiveCorrect = nextConsecutiveCorrect(current, now);
  const currentDay = localDayOrdinal(now);
  const oldEnough = current.last_wrong_at === null || currentDay - localDayOrdinal(current.last_wrong_at) >= 2;
  const resolved = consecutiveCorrect >= 3 && oldEnough;
  const active = resolved ? false : Boolean(current.active);

  await sqlite.prepare(`UPDATE wrong_word_states SET consecutive_correct = ?, last_correct_at = ?, active = ?,
    resolved_at = ?, updated_at = ? WHERE word_id = ?`)
    .run(consecutiveCorrect, now, active ? 1 : 0, resolved ? now : null, now, wordId);
  return { active, consecutiveCorrect };
}
