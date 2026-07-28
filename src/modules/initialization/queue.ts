import { sqlite } from "@/db/client";
import type {
  AiTaskType,
  InitializationField,
  InitializationMode,
  InitializationProviderId,
  InitializationTaskOptions,
  ProviderStrategy,
} from "@/lib/types";
import { dictionaryContentFromRow } from "@/modules/dictionary/content";
import {
  normalizeRequestedFields,
  requestedFieldStatusForLanguages,
} from "@/modules/dictionary/selection";
import {
  maxAttemptsFromSettings,
  parseStringArray,
  setWordOperationalStatus,
  uniqueOrdered,
} from "./shared";
export function queueWordInitialization(
  wordId: number,
  mode: InitializationMode = "FILL_MISSING_FIELDS",
  priority = 100,
  options: InitializationTaskOptions = {},
): number {
  return queueAiTask(wordId, "INITIALIZE", mode, priority, options);
}

export function queueAiTask(
  wordId: number,
  taskType: AiTaskType,
  mode: InitializationMode = "FILL_MISSING_FIELDS",
  priority = 100,
  options: InitializationTaskOptions = {},
): number {
  const word = sqlite.prepare("SELECT id FROM words WHERE id = ?").get(wordId);
  if (!word) throw new Error("WORD_NOT_FOUND");
  const now = Date.now();
  const maxAttempts = maxAttemptsFromSettings();
  const active = sqlite.prepare(`SELECT id, mode, requested_fields_json, requested_providers_json, provider_strategy
    FROM initialization_jobs WHERE word_id = ? AND task_type = ? AND status IN ('QUEUED','RUNNING') LIMIT 1`)
    .get(wordId, taskType) as {
      id: number; mode: InitializationMode; requested_fields_json: string | null;
      requested_providers_json: string | null; provider_strategy: ProviderStrategy | null;
    } | undefined;
  const requestedFields = taskType === "INITIALIZE" ? normalizeRequestedFields(options.requestedFields) : [];
  const requestedProviders = taskType === "INITIALIZE" ? uniqueOrdered(options.requestedProviders) : [];
  const providerStrategy = options.providerStrategy ?? "PARALLEL_MERGE";
  if (active) {
    const activeFields = parseStringArray<InitializationField>(active.requested_fields_json);
    const activeProviders = parseStringArray<InitializationProviderId>(active.requested_providers_json);
    const mergedFields = taskType === "INITIALIZE"
      ? (!activeFields.length || !requestedFields.length ? [] : uniqueOrdered(activeFields, requestedFields))
      : activeFields;
    const mergedProviders = taskType === "INITIALIZE"
      ? (!activeProviders.length || !requestedProviders.length ? [] : uniqueOrdered(activeProviders, requestedProviders))
      : activeProviders;
    sqlite.prepare(`UPDATE initialization_jobs SET mode = ?, priority = MAX(priority, ?), max_attempts = MAX(max_attempts, ?),
      requested_fields_json = ?, requested_providers_json = ?, provider_strategy = ?, available_at = ?, updated_at = ? WHERE id = ?`)
      .run(
        strongerInitializationMode(active.mode, mode), priority, maxAttempts,
        taskType === "INITIALIZE" ? (mergedFields.length ? JSON.stringify(mergedFields) : null) : active.requested_fields_json,
        taskType === "INITIALIZE" ? (mergedProviders.length ? JSON.stringify(mergedProviders) : null) : active.requested_providers_json,
        options.providerStrategy ?? active.provider_strategy ?? "PARALLEL_MERGE",
        now, now, active.id,
      );
    return active.id;
  }
  const supplementalFields = taskType === "MNEMONIC" ? ["learning.mnemonic"] : taskType === "EXAMPLE_TRANSLATIONS" ? ["examples.translation"] : null;
  const result = sqlite.prepare(`INSERT INTO initialization_jobs
    (word_id, task_type, mode, requested_fields_json, requested_providers_json, provider_strategy,
     status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, 'QUEUED', ?, 0, ?, ?, ?, ?)`)
    .run(
      wordId, taskType, mode,
      taskType === "INITIALIZE" ? (requestedFields.length ? JSON.stringify(requestedFields) : null) : JSON.stringify(supplementalFields),
      taskType === "INITIALIZE" && requestedProviders.length ? JSON.stringify(requestedProviders) : null,
      providerStrategy, priority, maxAttempts, now, now, now,
    );
  if (taskType === "INITIALIZE") setWordOperationalStatus(wordId, "QUEUED", now);
  return Number(result.lastInsertRowid);
}

export interface QueueInitializationResult {
  requestedWords: number;
  selectedWords: number;
  skippedWords: number;
  createdJobs: number;
  updatedJobs: number;
  mode: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE">;
}

export function queueSelectedInitialization(
  wordIds: number[],
  mode: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE"> = "FILL_MISSING_FIELDS",
  options: InitializationTaskOptions = {},
): QueueInitializationResult {
  const requestedIds = [...new Set(wordIds.filter((id) => Number.isInteger(id) && id > 0))];
  if (!requestedIds.length) return { requestedWords: 0, selectedWords: 0, skippedWords: 0, createdJobs: 0, updatedJobs: 0, mode };

  const placeholders = requestedIds.map(() => "?").join(", ");
  const existingIds = new Set((sqlite.prepare(`SELECT id FROM words WHERE id IN (${placeholders})`).all(...requestedIds) as Array<{ id: number }>)
    .map((row) => row.id));
  let createdJobs = 0;
  let updatedJobs = 0;

  sqlite.transaction(() => {
    for (const wordId of existingIds) {
      const before = sqlite.prepare(`SELECT id FROM initialization_jobs
        WHERE word_id = ? AND task_type = 'INITIALIZE' AND status IN ('QUEUED','RUNNING') LIMIT 1`).get(wordId) as { id: number } | undefined;
      queueWordInitialization(wordId, mode, 90, options);
      if (before) updatedJobs += 1;
      else createdJobs += 1;
    }
  }).immediate();

  return {
    requestedWords: requestedIds.length,
    selectedWords: existingIds.size,
    skippedWords: requestedIds.length - existingIds.size,
    createdJobs,
    updatedJobs,
    mode,
  };
}

export interface ConfiguredInitializationInput extends InitializationTaskOptions {
  wordIds?: number[];
  mode?: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE">;
  onlyMissing?: boolean;
}

function configuredCandidates(input: ConfiguredInitializationInput) {
  const requestedFields = normalizeRequestedFields(input.requestedFields);
  const requestedIds = input.wordIds?.length
    ? [...new Set(input.wordIds.filter((id) => Number.isInteger(id) && id > 0))]
    : null;
  const where = requestedIds ? `WHERE w.id IN (${requestedIds.map(() => "?").join(",")})` : "";
  const rows = sqlite.prepare(`SELECT w.id AS selected_word_id, w.term,
      w.source_language, w.target_language, wc.*
    FROM words w LEFT JOIN word_contents wc ON wc.word_id = w.id ${where} ORDER BY w.id ASC`)
    .all(...(requestedIds ?? [])) as Array<Record<string, unknown>>;
  const onlyMissing = input.onlyMissing ?? input.mode !== "FORCE_OVERWRITE";
  const candidates = rows.filter((row) => {
    if (!onlyMissing || !requestedFields.length) return true;
    return requestedFieldStatusForLanguages(
      dictionaryContentFromRow(row),
      requestedFields,
      String(row.source_language),
      String(row.target_language),
    ) !== "READY";
  });
  return { requestedFields, requestedIds, rows, candidates };
}

export function previewConfiguredInitialization(input: ConfiguredInitializationInput) {
  const { requestedFields, requestedIds, rows, candidates } = configuredCandidates(input);
  return {
    scope: requestedIds ? "SELECTED" as const : "ALL" as const,
    requestedWords: requestedIds?.length ?? rows.length,
    existingWords: rows.length,
    selectedWords: candidates.length,
    skippedExisting: rows.length - candidates.length,
    requestedFields,
    requestedProviders: uniqueOrdered(input.requestedProviders),
    providerStrategy: input.providerStrategy ?? "PARALLEL_MERGE",
    mode: input.mode ?? "FILL_MISSING_FIELDS",
    sample: candidates.slice(0, 8).map((row) => ({ id: Number(row.selected_word_id), term: String(row.term) })),
  };
}

export function queueConfiguredInitialization(input: ConfiguredInitializationInput) {
  const preview = previewConfiguredInitialization(input);
  const { candidates } = configuredCandidates(input);
  const queued = queueSelectedInitialization(
    candidates.map((row) => Number(row.selected_word_id)),
    input.mode ?? "FILL_MISSING_FIELDS",
    input,
  );
  return { ...preview, createdJobs: queued.createdJobs, updatedJobs: queued.updatedJobs };
}


function strongerInitializationMode(current: InitializationMode, requested: InitializationMode): InitializationMode {
  const weight: Record<InitializationMode, number> = {
    SKIP_INITIALIZED: 1,
    FILL_MISSING_FIELDS: 2,
    FORCE_OVERWRITE: 3,
  };
  return weight[requested] > weight[current] ? requested : current;
}

export function queueBulkInitialization(
  mode: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE"> = "FILL_MISSING_FIELDS",
  onlyWithoutAi = true,
  options: InitializationTaskOptions = {},
) {
  const total = (sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count: number }).count;
  const aiFilter = onlyWithoutAi
    ? `WHERE NOT EXISTS (
        SELECT 1 FROM provider_attempts pa
        WHERE pa.word_id = w.id AND pa.provider_id LIKE 'ai:%' AND pa.status = 'SUCCESS'
      )`
    : "";
  const candidates = sqlite.prepare(`SELECT w.id FROM words w ${aiFilter} ORDER BY w.id ASC`).all() as Array<{ id: number }>;
  const queued = queueSelectedInitialization(candidates.map((candidate) => candidate.id), mode, options);
  return {
    totalWords: total,
    selectedWords: queued.selectedWords,
    skippedAiInitialized: onlyWithoutAi ? total - candidates.length : 0,
    createdJobs: queued.createdJobs,
    updatedJobs: queued.updatedJobs,
    mode,
  };
}

export function retryFailedJobs(jobIds: number[]): number {
  const now = Date.now();
  const statement = sqlite.prepare(`UPDATE initialization_jobs SET status = 'QUEUED', attempt_count = 0,
    available_at = ?, locked_at = NULL, locked_by = NULL, last_error = NULL, last_error_code = NULL,
    completed_at = NULL, updated_at = ? WHERE id = ? AND status = 'FAILED'`);
  let changed = 0;
  sqlite.transaction(() => {
    for (const id of jobIds) {
      const job = sqlite.prepare("SELECT word_id, task_type FROM initialization_jobs WHERE id = ?").get(id) as { word_id: number; task_type: AiTaskType } | undefined;
      const result = statement.run(now, now, id);
      changed += result.changes;
      if (result.changes && job?.task_type === "INITIALIZE") setWordOperationalStatus(job.word_id, "QUEUED", now);
    }
  })();
  return changed;
}
