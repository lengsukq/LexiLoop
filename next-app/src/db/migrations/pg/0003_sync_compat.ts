// Schema v2 compatibility for lossless bidirectional sync with Flutter clients:
// - words.is_personal separates personal vocabulary from installed word packs.
// - word_packs / word_pack_items mirror Drift tables so pack memberships survive cloud round-trips.
export const PG_SYNC_COMPAT_SQL = `
ALTER TABLE words ADD COLUMN IF NOT EXISTS is_personal INTEGER NOT NULL DEFAULT 1;
CREATE INDEX IF NOT EXISTS words_personal_idx ON words(is_personal);

CREATE TABLE IF NOT EXISTS word_packs (
  id TEXT PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'CUSTOM',
  description TEXT NOT NULL DEFAULT '',
  version TEXT NOT NULL,
  content_mode TEXT NOT NULL DEFAULT 'ECDICT_BASE',
  word_count BIGINT NOT NULL DEFAULT 0,
  include_in_daily_study INTEGER NOT NULL DEFAULT 0,
  sha256 TEXT NOT NULL DEFAULT '',
  source_url TEXT,
  installed_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS word_pack_items (
  pack_id TEXT NOT NULL REFERENCES word_packs(id) ON DELETE CASCADE,
  word_id BIGINT NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  rank BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (pack_id, word_id)
);
CREATE INDEX IF NOT EXISTS word_pack_items_word_idx ON word_pack_items(word_id);
CREATE INDEX IF NOT EXISTS word_pack_items_pack_rank_idx ON word_pack_items(pack_id, rank);
`;
