ALTER TABLE words ADD COLUMN content_type TEXT NOT NULL DEFAULT 'WORD'
  CHECK(content_type IN ('WORD','PHRASE','SENTENCE'));
UPDATE words SET content_type = entry_type WHERE entry_type IN ('WORD','PHRASE');

ALTER TABLE word_contents ADD COLUMN sentence_analysis_json TEXT NOT NULL DEFAULT
  '{"grammarNotes":[],"keyExpressions":[],"variations":[]}';

CREATE TABLE IF NOT EXISTS manual_previews (
  token TEXT PRIMARY KEY,
  input_text TEXT NOT NULL,
  normalized_term TEXT NOT NULL,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  source_language_name TEXT,
  target_language_name TEXT,
  content_type TEXT NOT NULL CHECK(content_type IN ('WORD','PHRASE','SENTENCE')),
  content_json TEXT NOT NULL,
  provider_attempts_json TEXT NOT NULL DEFAULT '[]',
  existing_word_id INTEGER REFERENCES words(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'PREVIEW' CHECK(status IN ('PREVIEW','COMMITTED','EXPIRED')),
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  committed_at INTEGER
);
CREATE INDEX IF NOT EXISTS manual_previews_expiry_idx ON manual_previews(status, expires_at);
CREATE INDEX IF NOT EXISTS manual_previews_identity_idx ON manual_previews(normalized_term, source_language, target_language);
