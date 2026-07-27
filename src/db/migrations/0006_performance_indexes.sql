-- Performance indexes for maintenance tasks and common queries
CREATE INDEX IF NOT EXISTS study_session_items_word_status_idx ON study_session_items(word_id, status);
CREATE INDEX IF NOT EXISTS study_session_items_status_answered_idx ON study_session_items(status, answered_at);
CREATE INDEX IF NOT EXISTS wrong_word_states_decay_idx ON wrong_word_states(active, last_wrong_at);
CREATE INDEX IF NOT EXISTS initialization_jobs_retry_idx ON initialization_jobs(status, attempt_count, completed_at);
CREATE INDEX IF NOT EXISTS study_sessions_completed_idx ON study_sessions(completed_at, started_at);
