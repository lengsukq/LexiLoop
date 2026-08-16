import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import type {
  AiTaskType,
  InitializationField,
  InitializationMode,
  InitializationProviderId,
  InitializationTaskOptions,
  ProviderStrategy,
} from "@/lib/types";
import {
  normalizeRequestedFields,
} from "@/modules/dictionary/selection";
import {
  maxAttemptsFromSettings,
  parseStringArray,
  setWordOperationalStatus,
  uniqueOrdered,
} from "./shared";

export { previewConfiguredInitialization, queueConfiguredInitialization } from "./configured";
export { queueBulkInitialization, retryFailedJobs } from "./bulk";

function strongerInitializationMode(current: InitializationMode, requested: InitializationMode): InitializationMode {
  const weight: Record<InitializationMode, number> = {
    SKIP_INITIALIZED: 1,
    FILL_MISSING_FIELDS: 2,
    FORCE_OVERWRITE: 3,
  };
  return weight[requested] > weight[current] ? requested : current;
}
export async function queueWordInitialization(
  wordId: number,
  mode: InitializationMode = "FILL_MISSING_FIELDS",
  priority = 100,
  options: InitializationTaskOptions = {},
): Promise<number> {
  return queueAiTask(wordId, "INITIALIZE", mode, priority, options);
}

export async function queueAiTask(
  wordId: number,
  taskType: AiTaskType,
  mode: InitializationMode = "FILL_MISSING_FIELDS",
  priority = 100,
  options: InitializationTaskOptions = {},
): Promise<number> {
  const word = await sqlite.prepare("SELECT id FROM words WHERE id = ?").get(wordId);
  if (!word) throw new ApiError("WORD_NOT_FOUND");
  const now = Date.now();
  const maxAttempts = await maxAttemptsFromSettings();
  const active = await sqlite.prepare(`SELECT id, mode, requested_fields_json, requested_providers_json, provider_strategy
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
    await sqlite.prepare(`UPDATE initialization_jobs SET mode = ?, priority = GREATEST(priority, ?), max_attempts = GREATEST(max_attempts, ?),
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
  const result = await sqlite.prepare(`INSERT INTO initialization_jobs
    (word_id, task_type, mode, requested_fields_json, requested_providers_json, provider_strategy,
     status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, 'QUEUED', ?, 0, ?, ?, ?, ?)`)
    .run(
      wordId, taskType, mode,
      taskType === "INITIALIZE" ? (requestedFields.length ? JSON.stringify(requestedFields) : null) : JSON.stringify(supplementalFields),
      taskType === "INITIALIZE" && requestedProviders.length ? JSON.stringify(requestedProviders) : null,
      providerStrategy, priority, maxAttempts, now, now, now,
    );
  if (taskType === "INITIALIZE") await setWordOperationalStatus(wordId, "QUEUED", now);
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

export async function queueSelectedInitialization(
  wordIds: number[],
  mode: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE"> = "FILL_MISSING_FIELDS",
  options: InitializationTaskOptions = {},
): Promise<QueueInitializationResult> {
  const requestedIds = [...new Set(wordIds.filter((id) => Number.isInteger(id) && id > 0))];
  if (!requestedIds.length) return { requestedWords: 0, selectedWords: 0, skippedWords: 0, createdJobs: 0, updatedJobs: 0, mode };

  const placeholders = requestedIds.map(() => "?").join(", ");
  const existingIds = new Set((await sqlite.prepare(`SELECT id FROM words WHERE id IN (${placeholders})`).all(...requestedIds) as Array<{ id: number }>)
    .map((row) => row.id));
  let createdJobs = 0;
  let updatedJobs = 0;

  await sqlite.transaction(async () => {
    for (const wordId of existingIds) {
      const before = await sqlite.prepare(`SELECT id FROM initialization_jobs
        WHERE word_id = ? AND task_type = 'INITIALIZE' AND status IN ('QUEUED','RUNNING') LIMIT 1`).get(wordId) as { id: number } | undefined;
      await queueWordInitialization(wordId, mode, 90, options);
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
