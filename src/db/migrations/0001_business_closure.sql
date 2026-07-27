ALTER TABLE study_sessions ADD COLUMN skipped_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE study_session_items ADD COLUMN skip_reason TEXT;
ALTER TABLE import_batches ADD COLUMN rolled_back_at INTEGER;
