// Materialized per-word review statistics (was missing from 0000_pg_initial.sql).
export const PG_WORD_REVIEW_STATS_SQL = `
CREATE TABLE IF NOT EXISTS word_review_stats (
  word_id BIGINT PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  total_reviews BIGINT NOT NULL DEFAULT 0,
  correct_reviews BIGINT NOT NULL DEFAULT 0,
  recent_again_30d BIGINT NOT NULL DEFAULT 0,
  recent_again_14d BIGINT NOT NULL DEFAULT 0,
  recent_wrong_14d BIGINT NOT NULL DEFAULT 0,
  recent_hard_14d BIGINT NOT NULL DEFAULT 0,
  total_duration_ms BIGINT NOT NULL DEFAULT 0,
  duration_count BIGINT NOT NULL DEFAULT 0,
  last_reviewed_at BIGINT,
  updated_at BIGINT NOT NULL DEFAULT 0
);
`;
