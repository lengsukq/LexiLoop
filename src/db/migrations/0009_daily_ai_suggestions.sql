-- Daily AI study review and recommended practice source.
ALTER TABLE study_sessions ADD COLUMN source_type TEXT;
CREATE INDEX IF NOT EXISTS study_sessions_source_idx ON study_sessions(source_type, completed_at, started_at);

CREATE TABLE IF NOT EXISTS daily_ai_suggestions (
  date_key TEXT PRIMARY KEY,
  source_date_key TEXT NOT NULL,
  quality_score INTEGER,
  metrics_json TEXT NOT NULL DEFAULT '{}',
  content_json TEXT NOT NULL DEFAULT '{}',
  recommended_items_json TEXT NOT NULL DEFAULT '[]',
  generator TEXT NOT NULL DEFAULT 'RULE_BASED' CHECK(generator IN ('AI','RULE_BASED')),
  provider_id TEXT,
  model TEXT,
  generation_warning TEXT,
  generated_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS daily_ai_suggestions_generated_idx ON daily_ai_suggestions(generated_at);
