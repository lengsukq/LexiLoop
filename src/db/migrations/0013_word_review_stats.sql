-- Materialized per-word review statistics to avoid repeated full-table
-- aggregation of review_logs during candidate selection and mastery scoring.
CREATE TABLE IF NOT EXISTS word_review_stats (
  word_id INTEGER PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  total_reviews INTEGER NOT NULL DEFAULT 0,
  correct_reviews INTEGER NOT NULL DEFAULT 0,
  recent_again_30d INTEGER NOT NULL DEFAULT 0,
  recent_again_14d INTEGER NOT NULL DEFAULT 0,
  recent_wrong_14d INTEGER NOT NULL DEFAULT 0,
  recent_hard_14d INTEGER NOT NULL DEFAULT 0,
  total_duration_ms INTEGER NOT NULL DEFAULT 0,
  duration_count INTEGER NOT NULL DEFAULT 0,
  last_reviewed_at INTEGER,
  updated_at INTEGER NOT NULL DEFAULT 0
);

-- Backfill existing history once; the 14/30 day windows are relative to the
-- migration time and self-correct on each subsequent answer submission.
INSERT INTO word_review_stats (
  word_id, total_reviews, correct_reviews, recent_again_30d, recent_again_14d,
  recent_wrong_14d, recent_hard_14d, total_duration_ms, duration_count,
  last_reviewed_at, updated_at
)
SELECT
  word_id,
  count(*),
  sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END),
  sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= (strftime('%s','now')*1000 - 2592000000) THEN 1 ELSE 0 END),
  sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= (strftime('%s','now')*1000 - 1209600000) THEN 1 ELSE 0 END),
  sum(CASE WHEN is_correct = 0 AND reviewed_at >= (strftime('%s','now')*1000 - 1209600000) THEN 1 ELSE 0 END),
  sum(CASE WHEN rating = 'HARD' AND reviewed_at >= (strftime('%s','now')*1000 - 1209600000) THEN 1 ELSE 0 END),
  sum(CASE WHEN duration_ms IS NOT NULL AND duration_ms > 0 THEN duration_ms ELSE 0 END),
  sum(CASE WHEN duration_ms IS NOT NULL AND duration_ms > 0 THEN 1 ELSE 0 END),
  max(reviewed_at),
  (strftime('%s','now')*1000)
FROM review_logs
GROUP BY word_id;

-- Support the NOT EXISTS availability lookups keyed on word_id.
CREATE INDEX IF NOT EXISTS study_session_items_word_idx
  ON study_session_items(word_id, status, answered_at);
