import { sqlite } from "@/db/client";
import type { LeaderboardSummary, TopScoreEntry } from "@/lib/types";

export const LEADERBOARD_LIMIT = 10;

interface ScoreRow {
  score: number;
  max_combo: number;
  accuracy: number;
  elapsed_ms: number;
  played_at: number;
}

function toEntry(row: ScoreRow, current: { score: number; playedAt: number }): TopScoreEntry {
  return {
    score: row.score,
    maxCombo: row.max_combo,
    accuracy: row.accuracy,
    elapsedMs: row.elapsed_ms,
    playedAt: row.played_at,
    isCurrent: row.played_at === current.playedAt && row.score === current.score,
  };
}

export async function recordScore(input: {
  gameMode: string;
  score: number;
  maxCombo: number;
  accuracy: number;
  elapsedMs: number;
  playedAt?: number;
}): Promise<LeaderboardSummary> {
  const playedAt = input.playedAt ?? Date.now();
  const score = Math.max(0, Math.round(input.score));

  await sqlite.prepare(`INSERT INTO game_high_scores
    (game_mode, score, max_combo, accuracy, elapsed_ms, played_at, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)`)
    .run(input.gameMode, score, Math.max(0, input.maxCombo), Math.max(0, input.accuracy), Math.max(0, input.elapsedMs), playedAt, playedAt);

  const better = await sqlite.prepare(`SELECT COUNT(*) AS c FROM game_high_scores
    WHERE game_mode = ? AND score > ?`).get(input.gameMode, score) as { c: number };
  const rank = better.c + 1;

  const rows = await sqlite.prepare(`SELECT score, max_combo, accuracy, elapsed_ms, played_at
    FROM game_high_scores WHERE game_mode = ?
    ORDER BY score DESC, played_at ASC LIMIT ?`).all(input.gameMode, LEADERBOARD_LIMIT) as ScoreRow[];

  const current = { score, playedAt };
  const top = rows.map((row) => toEntry(row, current));

  return {
    rank,
    inTop10: rank <= LEADERBOARD_LIMIT,
    isNewBest: rank === 1,
    best: top[0]?.score ?? score,
    top,
  };
}
