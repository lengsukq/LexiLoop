// Cumulative final schema for PostgreSQL mode.
// Column types keep the exact semantics of the SQLite schema:
// - id/timestamp columns are BIGINT because epoch-millisecond timestamps exceed 32-bit INTEGER.
// - boolean-style columns stay INTEGER with 0/1 so existing `= 1` predicates keep working.
// - all *_json payloads stay TEXT (JSON strings), matching the SQLite storage format.
export const PG_INITIAL_SQL = `
CREATE TABLE IF NOT EXISTS words (
  id BIGSERIAL PRIMARY KEY,
  term TEXT NOT NULL,
  normalized_term TEXT NOT NULL,
  source_language TEXT NOT NULL,
  target_language TEXT NOT NULL,
  source_language_name TEXT,
  target_language_name TEXT,
  entry_type TEXT NOT NULL CHECK(entry_type IN ('WORD','PHRASE')),
  content_type TEXT NOT NULL DEFAULT 'WORD' CHECK(content_type IN ('WORD','PHRASE','SENTENCE')),
  source_created_at BIGINT,
  initialization_status TEXT NOT NULL DEFAULT 'PENDING' CHECK(initialization_status IN ('PENDING','QUEUED','RUNNING','READY','PARTIAL','FAILED','DISABLED')),
  mastery_level TEXT NOT NULL DEFAULT 'NEW' CHECK(mastery_level IN ('NEW','LEARNING','FAMILIAR','PROFICIENT','MASTERED')),
  mastery_score BIGINT NOT NULL DEFAULT 0,
  is_suspended INTEGER NOT NULL DEFAULT 0,
  user_note TEXT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS words_identity_unique ON words(normalized_term, source_language, target_language);
CREATE INDEX IF NOT EXISTS words_status_idx ON words(initialization_status);
CREATE INDEX IF NOT EXISTS words_mastery_idx ON words(mastery_level);
CREATE INDEX IF NOT EXISTS words_created_idx ON words(created_at);

CREATE TABLE IF NOT EXISTS word_contents (
  word_id BIGINT PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  definitions_json TEXT NOT NULL DEFAULT '[]',
  pronunciations_json TEXT NOT NULL DEFAULT '[]',
  examples_json TEXT NOT NULL DEFAULT '[]',
  phrases_json TEXT NOT NULL DEFAULT '[]',
  forms_json TEXT NOT NULL DEFAULT '[]',
  synonyms_json TEXT NOT NULL DEFAULT '[]',
  antonyms_json TEXT NOT NULL DEFAULT '[]',
  word_family_json TEXT NOT NULL DEFAULT '[]',
  confused_words_json TEXT NOT NULL DEFAULT '[]',
  roots_json TEXT NOT NULL DEFAULT '[]',
  affixes_json TEXT NOT NULL DEFAULT '[]',
  summary_json TEXT NOT NULL DEFAULT '{"shortDefinition":null,"translation":null,"cefrLevel":null,"frequency":null}',
  learning_json TEXT NOT NULL DEFAULT '{"pronunciationTip":null,"mnemonic":null,"commonMistakes":[]}',
  sentence_analysis_json TEXT NOT NULL DEFAULT '{"grammarPattern":null,"grammarExplanation":null,"grammarNotes":[],"keyExpressions":[],"similarExamples":[],"variations":[]}',
  tags_json TEXT NOT NULL DEFAULT '[]',
  provider_metadata_json TEXT NOT NULL DEFAULT '[]',
  content_source TEXT NOT NULL DEFAULT 'MIXED',
  content_version BIGINT NOT NULL DEFAULT 1,
  initialized_at BIGINT,
  updated_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS study_sessions (
  id BIGSERIAL PRIMARY KEY,
  session_type TEXT NOT NULL CHECK(session_type IN ('DAILY','NEW_WORDS','DUE_REVIEW','WRONG_WORDS','LISTENING','SPELLING')),
  source_type TEXT,
  started_at BIGINT NOT NULL,
  completed_at BIGINT,
  planned_count BIGINT NOT NULL DEFAULT 0,
  completed_count BIGINT NOT NULL DEFAULT 0,
  correct_count BIGINT NOT NULL DEFAULT 0,
  wrong_count BIGINT NOT NULL DEFAULT 0,
  skipped_count BIGINT NOT NULL DEFAULT 0,
  duration_ms BIGINT,
  created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS study_sessions_started_idx ON study_sessions(started_at);
CREATE INDEX IF NOT EXISTS study_sessions_completed_idx ON study_sessions(completed_at, started_at);
CREATE INDEX IF NOT EXISTS study_sessions_source_idx ON study_sessions(source_type, completed_at, started_at);

CREATE TABLE IF NOT EXISTS study_session_items (
  id BIGSERIAL PRIMARY KEY,
  study_session_id BIGINT NOT NULL REFERENCES study_sessions(id) ON DELETE CASCADE,
  position DOUBLE PRECISION NOT NULL,
  word_id BIGINT NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  task_type TEXT NOT NULL CHECK(task_type IN ('NEW','REVIEW','WRONG','LISTENING','SPELLING')),
  question_type TEXT NOT NULL CHECK(question_type IN ('EN_TO_ZH','EN_TO_ZH_CHOICE','ZH_TO_EN_CHOICE','ZH_TO_EN_SPELLING','LISTENING_SPELLING','CLOZE_SENTENCE','LISTENING_CHOICE','LETTER_BANK')),
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','ANSWERED','SKIPPED')),
  answered_at BIGINT,
  skip_reason TEXT,
  created_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS study_session_items_position_unique ON study_session_items(study_session_id, position);
CREATE INDEX IF NOT EXISTS study_session_items_session_idx ON study_session_items(study_session_id, status);
CREATE INDEX IF NOT EXISTS study_session_items_word_status_idx ON study_session_items(word_id, status);
CREATE INDEX IF NOT EXISTS study_session_items_status_answered_idx ON study_session_items(status, answered_at);
CREATE INDEX IF NOT EXISTS study_session_items_word_idx ON study_session_items(word_id, status, answered_at);

CREATE TABLE IF NOT EXISTS review_cards (
  word_id BIGINT PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  due_at BIGINT NOT NULL,
  stability DOUBLE PRECISION NOT NULL,
  difficulty DOUBLE PRECISION NOT NULL,
  elapsed_days BIGINT NOT NULL,
  scheduled_days BIGINT NOT NULL,
  reps BIGINT NOT NULL,
  lapses BIGINT NOT NULL,
  fsrs_state BIGINT NOT NULL,
  learning_steps BIGINT NOT NULL DEFAULT 0,
  last_review_at BIGINT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS review_cards_due_idx ON review_cards(due_at);

CREATE TABLE IF NOT EXISTS review_logs (
  id BIGSERIAL PRIMARY KEY,
  client_answer_id TEXT NOT NULL,
  word_id BIGINT NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  study_session_id BIGINT REFERENCES study_sessions(id) ON DELETE SET NULL,
  study_session_item_id BIGINT REFERENCES study_session_items(id) ON DELETE SET NULL,
  reviewed_at BIGINT NOT NULL,
  rating TEXT NOT NULL CHECK(rating IN ('AGAIN','HARD','GOOD','EASY')),
  question_type TEXT NOT NULL,
  presented_prompt TEXT,
  user_answer TEXT,
  expected_answer TEXT,
  is_correct INTEGER NOT NULL,
  duration_ms BIGINT,
  card_before_json TEXT,
  card_after_json TEXT,
  created_at BIGINT NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS review_logs_client_answer_unique ON review_logs(client_answer_id);
CREATE INDEX IF NOT EXISTS review_logs_word_idx ON review_logs(word_id, reviewed_at);
CREATE INDEX IF NOT EXISTS review_logs_session_idx ON review_logs(study_session_id);
CREATE INDEX IF NOT EXISTS review_logs_reviewed_idx ON review_logs(reviewed_at);

CREATE TABLE IF NOT EXISTS wrong_word_states (
  word_id BIGINT PRIMARY KEY REFERENCES words(id) ON DELETE CASCADE,
  active INTEGER NOT NULL DEFAULT 0,
  wrong_count BIGINT NOT NULL DEFAULT 0,
  hard_count BIGINT NOT NULL DEFAULT 0,
  consecutive_correct BIGINT NOT NULL DEFAULT 0,
  last_wrong_at BIGINT,
  last_correct_at BIGINT,
  resolved_at BIGINT,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS wrong_word_states_active_idx ON wrong_word_states(active, updated_at);
CREATE INDEX IF NOT EXISTS wrong_word_states_decay_idx ON wrong_word_states(active, last_wrong_at);

CREATE TABLE IF NOT EXISTS import_previews (
  token TEXT PRIMARY KEY,
  filename TEXT NOT NULL,
  file_hash TEXT NOT NULL,
  rows_json TEXT NOT NULL,
  expires_at BIGINT NOT NULL,
  created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS import_previews_expiry_idx ON import_previews(expires_at);

CREATE TABLE IF NOT EXISTS import_batches (
  id BIGSERIAL PRIMARY KEY,
  filename TEXT NOT NULL,
  file_hash TEXT,
  import_mode TEXT NOT NULL CHECK(import_mode IN ('SKIP_EXISTING','FILL_MISSING','FORCE_DICTIONARY_REFRESH')),
  reset_learning_progress INTEGER NOT NULL DEFAULT 0,
  total_rows BIGINT NOT NULL DEFAULT 0,
  valid_rows BIGINT NOT NULL DEFAULT 0,
  invalid_rows BIGINT NOT NULL DEFAULT 0,
  duplicate_rows BIGINT NOT NULL DEFAULT 0,
  created_words BIGINT NOT NULL DEFAULT 0,
  existing_words BIGINT NOT NULL DEFAULT 0,
  queued_initializations BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','COMMITTED','FAILED','ROLLED_BACK')),
  created_at BIGINT NOT NULL,
  completed_at BIGINT,
  rolled_back_at BIGINT
);
CREATE INDEX IF NOT EXISTS import_batches_created_idx ON import_batches(created_at);

CREATE TABLE IF NOT EXISTS import_rows (
  id BIGSERIAL PRIMARY KEY,
  import_batch_id BIGINT NOT NULL REFERENCES import_batches(id) ON DELETE CASCADE,
  row_number BIGINT NOT NULL,
  raw_json TEXT,
  normalized_term TEXT,
  word_id BIGINT REFERENCES words(id) ON DELETE SET NULL,
  status TEXT NOT NULL CHECK(status IN ('INVALID','DUPLICATE','NEW','EXISTING','IMPORTED','ERROR')),
  error_code TEXT,
  error_message TEXT,
  metadata_json TEXT,
  created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS import_rows_batch_idx ON import_rows(import_batch_id, row_number);

CREATE TABLE IF NOT EXISTS initialization_jobs (
  id BIGSERIAL PRIMARY KEY,
  word_id BIGINT NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  task_type TEXT NOT NULL DEFAULT 'INITIALIZE' CHECK(task_type IN ('INITIALIZE','MNEMONIC','EXAMPLE_TRANSLATIONS')),
  mode TEXT NOT NULL CHECK(mode IN ('SKIP_INITIALIZED','FILL_MISSING_FIELDS','FORCE_OVERWRITE')),
  requested_fields_json TEXT,
  requested_providers_json TEXT,
  provider_strategy TEXT NOT NULL DEFAULT 'PARALLEL_MERGE' CHECK(provider_strategy IN ('PARALLEL_MERGE','PRIORITY_FALLBACK')),
  status TEXT NOT NULL DEFAULT 'QUEUED' CHECK(status IN ('PENDING','QUEUED','RUNNING','READY','PARTIAL','FAILED','DISABLED')),
  priority BIGINT NOT NULL DEFAULT 0,
  attempt_count BIGINT NOT NULL DEFAULT 0,
  max_attempts BIGINT NOT NULL DEFAULT 5,
  available_at BIGINT,
  locked_at BIGINT,
  locked_by TEXT,
  last_error TEXT,
  last_error_code TEXT,
  created_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL,
  completed_at BIGINT
);
CREATE INDEX IF NOT EXISTS initialization_jobs_status_idx ON initialization_jobs(status, available_at, priority);
CREATE INDEX IF NOT EXISTS initialization_jobs_word_idx ON initialization_jobs(word_id);
CREATE INDEX IF NOT EXISTS initialization_jobs_task_type_idx ON initialization_jobs(task_type, status, available_at, priority);
CREATE UNIQUE INDEX IF NOT EXISTS initialization_jobs_active_word_task_unique
  ON initialization_jobs(word_id, task_type) WHERE status IN ('QUEUED','RUNNING');

CREATE TABLE IF NOT EXISTS provider_attempts (
  id BIGSERIAL PRIMARY KEY,
  initialization_job_id BIGINT REFERENCES initialization_jobs(id) ON DELETE CASCADE,
  word_id BIGINT NOT NULL REFERENCES words(id) ON DELETE CASCADE,
  provider_id TEXT NOT NULL,
  status TEXT NOT NULL CHECK(status IN ('SUCCESS','EMPTY','FAILED')),
  duration_ms BIGINT,
  fields_returned_json TEXT,
  error_code TEXT,
  error_message TEXT,
  metadata_json TEXT,
  created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS provider_attempts_job_idx ON provider_attempts(initialization_job_id);
CREATE INDEX IF NOT EXISTS provider_attempts_word_idx ON provider_attempts(word_id);

CREATE TABLE IF NOT EXISTS worker_heartbeats (
  worker_id TEXT PRIMARY KEY,
  status TEXT NOT NULL CHECK(status IN ('STARTING','IDLE','WORKING','STOPPING','ERROR')),
  current_job_id BIGINT,
  metadata_json TEXT,
  last_seen_at BIGINT NOT NULL,
  started_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value_json TEXT NOT NULL,
  updated_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_ai_suggestions (
  date_key TEXT PRIMARY KEY,
  source_date_key TEXT NOT NULL,
  quality_score BIGINT,
  metrics_json TEXT NOT NULL DEFAULT '{}',
  content_json TEXT NOT NULL DEFAULT '{}',
  recommended_items_json TEXT NOT NULL DEFAULT '[]',
  generator TEXT NOT NULL DEFAULT 'RULE_BASED' CHECK(generator IN ('AI','RULE_BASED')),
  provider_id TEXT,
  model TEXT,
  generation_warning TEXT,
  generated_at BIGINT NOT NULL,
  updated_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS daily_ai_suggestions_generated_idx ON daily_ai_suggestions(generated_at);

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
  existing_word_id BIGINT REFERENCES words(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'PREVIEW' CHECK(status IN ('PREVIEW','COMMITTED','EXPIRED')),
  expires_at BIGINT NOT NULL,
  created_at BIGINT NOT NULL,
  committed_at BIGINT
);
CREATE INDEX IF NOT EXISTS manual_previews_expiry_idx ON manual_previews(status, expires_at);
CREATE INDEX IF NOT EXISTS manual_previews_identity_idx ON manual_previews(normalized_term, source_language, target_language);

CREATE TABLE IF NOT EXISTS game_high_scores (
  id BIGSERIAL PRIMARY KEY,
  game_mode TEXT NOT NULL,
  score BIGINT NOT NULL,
  max_combo BIGINT NOT NULL DEFAULT 0,
  accuracy BIGINT NOT NULL DEFAULT 0,
  elapsed_ms BIGINT NOT NULL DEFAULT 0,
  played_at BIGINT NOT NULL,
  created_at BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS game_high_scores_mode_score_idx ON game_high_scores(game_mode, score DESC, played_at ASC);
`;
