-- Reuse the existing durable queue for every user-triggered AI operation.
ALTER TABLE initialization_jobs ADD COLUMN task_type TEXT NOT NULL DEFAULT 'INITIALIZE'
  CHECK(task_type IN ('INITIALIZE', 'MNEMONIC', 'EXAMPLE_TRANSLATIONS'));

DROP INDEX IF EXISTS initialization_jobs_active_word_unique;
CREATE INDEX IF NOT EXISTS initialization_jobs_task_type_idx ON initialization_jobs(task_type, status, available_at, priority);
CREATE UNIQUE INDEX IF NOT EXISTS initialization_jobs_active_word_task_unique
  ON initialization_jobs(word_id, task_type) WHERE status IN ('QUEUED', 'RUNNING');
