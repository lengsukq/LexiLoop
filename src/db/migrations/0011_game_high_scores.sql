-- Persist every finished game run so each game can show a personal top-10 board.
CREATE TABLE IF NOT EXISTS game_high_scores (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  game_mode TEXT NOT NULL,
  score INTEGER NOT NULL,
  max_combo INTEGER NOT NULL DEFAULT 0,
  accuracy INTEGER NOT NULL DEFAULT 0,
  elapsed_ms INTEGER NOT NULL DEFAULT 0,
  played_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS game_high_scores_mode_score_idx ON game_high_scores(game_mode, score DESC, played_at ASC);
