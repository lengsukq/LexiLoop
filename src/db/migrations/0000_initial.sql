PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS words (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  term TEXT NOT NULL,
  normalized_term TEXT NOT NULL,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  source_language_name TEXT,
  target_language_name TEXT,
  entry_type TEXT NOT NULL CHECK(entry_type IN ('WORD','PHRASE')),
  source_created_at INTEGER,
  initialization_status TEXT NOT NULL DEFAULT 'PENDING' CHECK(initialization_status IN ('PENDING','QUEUED','RUNNING','READY','PARTIAL','FAILED','DISABLED')),
  mastery_level TEXT NOT NULL DEFAULT 'NEW' CHECK(mastery_level IN ('NEW','LEARNING','FAMILIAR','PROFICIENT','MASTERED')),
  mastery_score INTEGER NOT NULL DEFAULT 0,
  is_suspended INTEGER NOT NULL DEFAULT 0,
  user_note TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS words_identity_unique ON words(normalized_term, source_language, target_language);
CREATE INDEX IF NOT EXISTS words_status_idx ON words(initialization_status);
CREATE INDEX IF NOT EXISTS words_mastery_idx ON words(mastery_level);
CREATE INDEX IF NOT EXISTS words_created_idx ON words(created_at);

CREATE TABLE IF NOT EXISTS word_contents (
  word_id INTEGER PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  definitions_json TEXT NOT NULL DEFAULT '[]',
  pronunciations_json TEXT NOT NULL DEFAULT '[]',
  examples_json TEXT NOT NULL DEFAULT '[]',
  phrases_json TEXT NOT NULL DEFAULT '[]',
  forms_json TEXT NOT NULL DEFAULT '[]',
  synonyms_json TEXT NOT NULL DEFAULT '[]',
  antonyms_json TEXT NOT NULL DEFAULT '[]',
  tags_json TEXT NOT NULL DEFAULT '[]',
  provider_metadata_json TEXT NOT NULL DEFAULT '[]',
  content_version INTEGER NOT NULL DEFAULT 1,
  initialized_at INTEGER,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS study_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_type TEXT NOT NULL CHECK(session_type IN ('DAILY','NEW_WORDS','DUE_REVIEW','WRONG_WORDS','LISTENING','SPELLING')),
  started_at INTEGER NOT NULL,
  completed_at INTEGER,
  planned_count INTEGER NOT NULL DEFAULT 0,
  completed_count INTEGER NOT NULL DEFAULT 0,
  correct_count INTEGER NOT NULL DEFAULT 0,
  wrong_count INTEGER NOT NULL DEFAULT 0,
  duration_ms INTEGER,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS study_sessions_started_idx ON study_sessions(started_at);

CREATE TABLE IF NOT EXISTS study_session_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  study_session_id INTEGER NOT NULL REFERENCES study_sessions(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  word_id INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  task_type TEXT NOT NULL CHECK(task_type IN ('NEW','REVIEW','WRONG','LISTENING','SPELLING')),
  question_type TEXT NOT NULL CHECK(question_type IN ('EN_TO_ZH','ZH_TO_EN_SPELLING','LISTENING_SPELLING')),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','ANSWERED','SKIPPED')),
  answered_at INTEGER,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS study_session_items_position_unique ON study_session_items(study_session_id, position);
CREATE INDEX IF NOT EXISTS study_session_items_session_idx ON study_session_items(study_session_id, status);

CREATE TABLE IF NOT EXISTS review_cards (
  word_id INTEGER PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  due_at INTEGER NOT NULL,
  stability REAL NOT NULL,
  difficulty REAL NOT NULL,
  elapsed_days INTEGER NOT NULL,
  scheduled_days INTEGER NOT NULL,
  reps INTEGER NOT NULL,
  lapses INTEGER NOT NULL,
  fsrs_state INTEGER NOT NULL,
  learning_steps INTEGER NOT NULL DEFAULT 0,
  last_review_at INTEGER,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS review_cards_due_idx ON review_cards(due_at);

CREATE TABLE IF NOT EXISTS review_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  client_answer_id TEXT NOT NULL,
  word_id INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  study_session_id INTEGER REFERENCES study_sessions(id) ON DELETE SET NULL,
  study_session_item_id INTEGER REFERENCES study_session_items(id) ON DELETE SET NULL,
  reviewed_at INTEGER NOT NULL,
  rating TEXT NOT NULL CHECK(rating IN ('AGAIN','HARD','GOOD','EASY')),
  question_type TEXT NOT NULL,
  presented_prompt TEXT,
  user_answer TEXT,
  expected_answer TEXT,
  is_correct INTEGER NOT NULL,
  duration_ms INTEGER,
  card_before_json TEXT,
  card_after_json TEXT,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS review_logs_client_answer_unique ON review_logs(client_answer_id);
CREATE INDEX IF NOT EXISTS review_logs_word_idx ON review_logs(word_id, reviewed_at);
CREATE INDEX IF NOT EXISTS review_logs_session_idx ON review_logs(study_session_id);
CREATE INDEX IF NOT EXISTS review_logs_reviewed_idx ON review_logs(reviewed_at);

CREATE TABLE IF NOT EXISTS wrong_word_states (
  word_id INTEGER PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  active INTEGER NOT NULL DEFAULT 0,
  wrong_count INTEGER NOT NULL DEFAULT 0,
  hard_count INTEGER NOT NULL DEFAULT 0,
  consecutive_correct INTEGER NOT NULL DEFAULT 0,
  last_wrong_at INTEGER,
  last_correct_at INTEGER,
  resolved_at INTEGER,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS wrong_word_states_active_idx ON wrong_word_states(active, updated_at);

CREATE TABLE IF NOT EXISTS import_previews (
  token TEXT PRIMARY KEY,
  filename TEXT NOT NULL,
  file_hash TEXT NOT NULL,
  rows_json TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS import_previews_expiry_idx ON import_previews(expires_at);

CREATE TABLE IF NOT EXISTS import_batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  filename TEXT NOT NULL,
  file_hash TEXT,
  import_mode TEXT NOT NULL CHECK(import_mode IN ('SKIP_EXISTING','FILL_MISSING','FORCE_DICTIONARY_REFRESH')),
  reset_learning_progress INTEGER NOT NULL DEFAULT 0,
  total_rows INTEGER NOT NULL DEFAULT 0,
  valid_rows INTEGER NOT NULL DEFAULT 0,
  invalid_rows INTEGER NOT NULL DEFAULT 0,
  duplicate_rows INTEGER NOT NULL DEFAULT 0,
  created_words INTEGER NOT NULL DEFAULT 0,
  existing_words INTEGER NOT NULL DEFAULT 0,
  queued_initializations INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','COMMITTED','FAILED','ROLLED_BACK')),
  created_at INTEGER NOT NULL,
  completed_at INTEGER
);
CREATE INDEX IF NOT EXISTS import_batches_created_idx ON import_batches(created_at);

CREATE TABLE IF NOT EXISTS import_rows (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  import_batch_id INTEGER NOT NULL REFERENCES import_batches(id) ON DELETE CASCADE,
  row_number INTEGER NOT NULL,
  raw_json TEXT,
  normalized_term TEXT,
  word_id INTEGER REFERENCES words(id) ON DELETE SET NULL,
  status TEXT NOT NULL CHECK(status IN ('INVALID','DUPLICATE','NEW','EXISTING','IMPORTED','ERROR')),
  error_code TEXT,
  error_message TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS import_rows_batch_idx ON import_rows(import_batch_id, row_number);

CREATE TABLE IF NOT EXISTS initialization_jobs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word_id INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  mode TEXT NOT NULL CHECK(mode IN ('SKIP_INITIALIZED','FILL_MISSING_FIELDS','FORCE_OVERWRITE')),
  requested_fields_json TEXT,
  status TEXT NOT NULL DEFAULT 'QUEUED' CHECK(status IN ('PENDING','QUEUED','RUNNING','READY','PARTIAL','FAILED','DISABLED')),
  priority INTEGER NOT NULL DEFAULT 0,
  attempt_count INTEGER NOT NULL DEFAULT 0,
  max_attempts INTEGER NOT NULL DEFAULT 5,
  available_at INTEGER,
  locked_at INTEGER,
  locked_by TEXT,
  last_error TEXT,
  last_error_code TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  completed_at INTEGER
);
CREATE INDEX IF NOT EXISTS initialization_jobs_status_idx ON initialization_jobs(status, available_at, priority);
CREATE INDEX IF NOT EXISTS initialization_jobs_word_idx ON initialization_jobs(word_id);
CREATE UNIQUE INDEX IF NOT EXISTS initialization_jobs_active_word_unique ON initialization_jobs(word_id) WHERE status IN ('QUEUED','RUNNING');

CREATE TABLE IF NOT EXISTS provider_attempts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  initialization_job_id INTEGER REFERENCES initialization_jobs(id) ON DELETE CASCADE,
  word_id INTEGER NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  provider_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('SUCCESS','EMPTY','FAILED')),
  duration_ms INTEGER,
  fields_returned_json TEXT,
  error_code TEXT,
  error_message TEXT,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS provider_attempts_job_idx ON provider_attempts(initialization_job_id);
CREATE INDEX IF NOT EXISTS provider_attempts_word_idx ON provider_attempts(word_id);

CREATE TABLE IF NOT EXISTS worker_heartbeats (
  worker_id TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK(status IN ('STARTING','IDLE','WORKING','STOPPING','ERROR')),
  current_job_id INTEGER,
  metadata_json TEXT,
  last_seen_at INTEGER NOT NULL,
  started_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
