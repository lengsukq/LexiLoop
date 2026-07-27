-- SQLite cannot ALTER CHECK constraints; recreate the table with EN_TO_ZH_CHOICE added.
CREATE TABLE study_session_items_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  study_session_id INTEGER NOT NULL REFERENCES study_sessions(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  word_id INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  task_type TEXT NOT NULL CHECK(task_type IN ('NEW','REVIEW','WRONG','LISTENING','SPELLING')),
  question_type TEXT NOT NULL CHECK(question_type IN ('EN_TO_ZH','EN_TO_ZH_CHOICE','ZH_TO_EN_SPELLING','LISTENING_SPELLING')),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','ANSWERED','SKIPPED')),
  answered_at INTEGER,
  skip_reason TEXT,
  created_at INTEGER NOT NULL
);
INSERT INTO study_session_items_new (id, study_session_id, position, word_id, task_type, question_type, status, answered_at, skip_reason, created_at)
  SELECT id, study_session_id, position, word_id, task_type, question_type, status, answered_at, skip_reason, created_at FROM study_session_items;
DROP TABLE study_session_items;
ALTER TABLE study_session_items_new RENAME TO study_session_items;
CREATE UNIQUE INDEX IF NOT EXISTS study_session_items_position_unique ON study_session_items(study_session_id, position);
CREATE INDEX IF NOT EXISTS study_session_items_session_idx ON study_session_items(study_session_id, status);
