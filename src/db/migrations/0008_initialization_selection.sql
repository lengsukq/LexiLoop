-- Store field-level and provider-level initialization choices on durable jobs.
ALTER TABLE initialization_jobs ADD COLUMN requested_providers_json TEXT;
ALTER TABLE initialization_jobs ADD COLUMN provider_strategy TEXT NOT NULL DEFAULT 'PARALLEL_MERGE'
  CHECK(provider_strategy IN ('PARALLEL_MERGE', 'PRIORITY_FALLBACK'));
