import { sqlite } from "@/db/client";
import type { ReviewRating } from "@/lib/types";
import type { WrongStateResult } from "./types";

const APP_TIMEZONE = process.env.APP_TIMEZONE ?? "Asia/Shanghai";
const DAY_MS = 86_400_000;
const dayFormatter = new Intl.DateTimeFormat("en-US", {
  timeZone: APP_TIMEZONE,
  year: "numeric",
  month: "numeric",
  day: "numeric",
});

interface WrongStateRow {
  active: number;
  wrong_count: number;
  hard_count: number;
  consecutive_correct: number;
  last_wrong_at: number | null;
  last_correct_at: number | null;
}

function localDayOrdinal(timestamp: number): number {
  const parts = dayFormatter.formatToParts(new Date(timestamp));
  const year = Number(parts.find((part) => part.type === "year")?.value ?? 0);
  const month = Number(parts.find((part) => part.type === "month")?.value ?? 1);
  const day = Number(parts.find((part) => part.type === "day")?.value ?? 1);
  return Math.floor(Date.UTC(year, month - 1, day) / DAY_MS);
}

function recordWrong(wordId: number, now: number): WrongStateResult {
  sqlite.prepare(`INSERT INTO wrong_word_states(word_id, active, wrong_count, hard_count, consecutive_correct, last_wrong_at, updated_at)
    VALUES (?, 1, 1, 0, 0, ?, ?)
    ON CONFLICT(word_id) DO UPDATE SET active = 1, wrong_count = wrong_count + 1,
      consecutive_correct = 0, last_wrong_at = excluded.last_wrong_at, resolved_at = NULL, updated_at = excluded.updated_at`)
    .run(wordId, now, now);
  return { active: true, consecutiveCorrect: 0 };
}

function recordHard(wordId: number, now: number): WrongStateResult {
  sqlite.prepare(`INSERT INTO wrong_word_states(word_id, active, wrong_count, hard_count, consecutive_correct, updated_at)
    VALUES (?, 1, 0, 1, 0, ?)
    ON CONFLICT(word_id) DO UPDATE SET active = 1, hard_count = hard_count + 1,
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

export function updateWrongWordState(wordId: number, rating: ReviewRating, isCorrect: boolean, now: number): WrongStateResult {
  const current = sqlite.prepare("SELECT * FROM wrong_word_states WHERE word_id = ?").get(wordId) as WrongStateRow | undefined;
  if (rating === "EASY") {
    if (!current) return { active: false, consecutiveCorrect: 1 };
    sqlite.prepare(`UPDATE wrong_word_states SET consecutive_correct = 1, last_correct_at = ?, active = 0,
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

  sqlite.prepare(`UPDATE wrong_word_states SET consecutive_correct = ?, last_correct_at = ?, active = ?,
    resolved_at = ?, updated_at = ? WHERE word_id = ?`)
    .run(consecutiveCorrect, now, active ? 1 : 0, resolved ? now : null, now, wordId);
  return { active, consecutiveCorrect };
}
