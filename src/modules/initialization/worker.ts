import { sqlite } from "@/db/client";
import type {
  AiTaskType,
  AppSettings,
  DictionaryContent,
  EntryType,
  InitializationField,
  InitializationMode,
  InitializationProviderId,
  InitializationStatus,
  ProviderAttempt,
  ProviderStrategy,
} from "@/lib/types";
import { runSupplementalTask } from "@/modules/ai-tasks/supplemental";
import { contentStatus, dictionaryContentFromRow, mergeDictionaryContent } from "@/modules/dictionary/content";
import { lookupDictionary } from "@/modules/dictionary/pipeline";
import {
  mergeRequestedFields,
  normalizeRequestedFields,
  requestedFieldStatusForLanguages,
} from "@/modules/dictionary/selection";
import { getSettings, settingsForAiAttempt } from "@/modules/settings/service";
import { MINUTE_MS, SECOND_MS } from "@/lib/time";
import { parseStringArray, setWordOperationalStatus } from "./shared";
import { queueAiTask } from "./queue";
import { saveWordContent } from "@/modules/words/save-content";
import type { ClaimedJob } from "./types";

export type { ClaimedJob } from "./types";

function retryDelayMs(attemptCount: number): number {
  return [5 * SECOND_MS, 30 * SECOND_MS, 2 * MINUTE_MS, 10 * MINUTE_MS, 30 * MINUTE_MS][Math.max(0, attemptCount - 1)]
    ?? 30 * MINUTE_MS;
}

function preserveUserContent(existing: DictionaryContent, refreshed: DictionaryContent): DictionaryContent {
  return mergeDictionaryContent({
    definitions: existing.definitions.filter((item) => item.isUserEdited),
    examples: existing.examples.filter((item) => item.isUserAdded),
  }, refreshed);
}
export async function recoverStaleJobs(staleAfterMs = 10 * MINUTE_MS): Promise<number> {
  const now = Date.now();
  const result = await sqlite.prepare(`UPDATE initialization_jobs
    SET status = 'QUEUED', locked_at = NULL, locked_by = NULL, available_at = ?,
        last_error = COALESCE(last_error, 'Worker lock expired'), last_error_code = 'STALE_LOCK', updated_at = ?
    WHERE status = 'RUNNING' AND locked_at IS NOT NULL AND locked_at < ?`)
    .run(now, now, now - staleAfterMs);
  const queuedWords = await sqlite.prepare("SELECT DISTINCT word_id FROM initialization_jobs WHERE status = 'QUEUED' AND task_type = 'INITIALIZE'").all() as Array<{ word_id: number }>;
  for (const job of queuedWords) await setWordOperationalStatus(job.word_id, "QUEUED", now);
  return result.changes;
}

export async function claimJobs(workerId: string, limit: number): Promise<ClaimedJob[]> {
  const now = Date.now();
  await recoverStaleJobs();
  const rows = await sqlite.prepare(`UPDATE initialization_jobs SET status = 'RUNNING', locked_at = ?, locked_by = ?,
      attempt_count = attempt_count + 1, updated_at = ?
    WHERE id IN (
      SELECT id FROM initialization_jobs
      WHERE status = 'QUEUED' AND attempt_count < max_attempts
        AND (available_at IS NULL OR available_at <= ?)
      ORDER BY priority DESC, created_at ASC
      LIMIT ?
      FOR UPDATE SKIP LOCKED
    )
    RETURNING id, word_id, task_type, mode, attempt_count, max_attempts,
      requested_fields_json, requested_providers_json, provider_strategy`).all(now, workerId, now, now, limit) as Array<{
        id: number; word_id: number; task_type: AiTaskType; mode: InitializationMode; attempt_count: number; max_attempts: number;
        requested_fields_json: string | null; requested_providers_json: string | null; provider_strategy: ProviderStrategy | null;
      }>;
  const claimed: ClaimedJob[] = [];
  for (const row of rows) {
    if (row.task_type === "INITIALIZE") await setWordOperationalStatus(row.word_id, "RUNNING", now);
    claimed.push({
      id: row.id,
      wordId: row.word_id,
      taskType: row.task_type,
      mode: row.mode,
      attemptCount: row.attempt_count,
      maxAttempts: row.max_attempts,
      requestedFields: parseStringArray<InitializationField>(row.requested_fields_json),
      requestedProviders: parseStringArray<InitializationProviderId>(row.requested_providers_json),
      providerStrategy: row.provider_strategy ?? "PARALLEL_MERGE",
    });
  }
  return claimed;
}

async function saveAttempts(jobId: number, wordId: number, attempts: ProviderAttempt[], now: number): Promise<void> {
  const insert = sqlite.prepare(`INSERT INTO provider_attempts
    (initialization_job_id, word_id, provider_id, status, duration_ms, fields_returned_json, error_code, error_message, metadata_json, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  for (const attempt of attempts) {
    await insert.run(jobId, wordId, attempt.providerId, attempt.status, attempt.durationMs, JSON.stringify(attempt.fieldsReturned), attempt.errorCode ?? null, attempt.errorMessage ?? null, attempt.metadata ? JSON.stringify(attempt.metadata) : null, now);
  }
}

async function saveContent(wordId: number, content: DictionaryContent, attempts: ProviderAttempt[], contentSource: string, now: number): Promise<void> {
  await saveWordContent(wordId, content, { providerMetadata: attempts, contentSource, now });
}

async function completeJob(job: ClaimedJob, status: InitializationStatus, now: number, wordStatus: InitializationStatus = status): Promise<void> {
  await sqlite.prepare(`UPDATE initialization_jobs SET status = ?, locked_at = NULL, locked_by = NULL,
    completed_at = ?, updated_at = ?, last_error = NULL, last_error_code = NULL WHERE id = ?`)
    .run(status, now, now, job.id);
  if (job.taskType === "INITIALIZE") await sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?").run(wordStatus, now, job.wordId);
}

/** 初始化成功后排队非事实内容；低优先级执行，不阻塞词典内容落库。 */
async function queueSupplementalTasks(
  wordId: number,
  content: DictionaryContent,
  settings: AppSettings,
  entryType: EntryType,
  sourceLanguage: string,
  targetLanguage: string,
): Promise<void> {
  const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!purpose.enabled || !provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) return;

  if (entryType === "SENTENCE") {
    const hasTargetTranslation = content.definitions.some((item) => item.language === targetLanguage && item.text.trim())
      || Boolean(content.summary.translation?.trim());
    if (!hasTargetTranslation) await queueAiTask(wordId, "EXAMPLE_TRANSLATIONS", "FILL_MISSING_FIELDS", 20);
    return;
  }

  if (sourceLanguage.startsWith("en") && !content.learning.mnemonic?.trim()) {
    await queueAiTask(wordId, "MNEMONIC", "FILL_MISSING_FIELDS", 20);
  }
}

async function failOrRetry(job: ClaimedJob, transient: boolean, errorCode: string, errorMessage: string, now: number): Promise<void> {
  if (transient && job.attemptCount < job.maxAttempts) {
    await sqlite.prepare(`UPDATE initialization_jobs SET status = 'QUEUED', locked_at = NULL, locked_by = NULL,
      available_at = ?, last_error = ?, last_error_code = ?, updated_at = ? WHERE id = ?`)
      .run(now + retryDelayMs(job.attemptCount), errorMessage, errorCode, now, job.id);
    if (job.taskType === "INITIALIZE") await setWordOperationalStatus(job.wordId, "QUEUED", now);
    return;
  }
  await sqlite.prepare(`UPDATE initialization_jobs SET status = 'FAILED', locked_at = NULL, locked_by = NULL,
    completed_at = ?, last_error = ?, last_error_code = ?, updated_at = ? WHERE id = ?`)
    .run(now, errorMessage, errorCode, now, job.id);
  if (job.taskType === "INITIALIZE") await setWordOperationalStatus(job.wordId, "FAILED", now);
}

export async function processJob(job: ClaimedJob): Promise<void> {
  if (job.taskType !== "INITIALIZE") {
    try {
      await runSupplementalTask(job.taskType, job.wordId, job.attemptCount);
      await completeJob(job, "READY", Date.now());
    } catch (error) {
      const text = String(error);
      const transient = !["WORD_NOT_FOUND", "AI_DISABLED", "AI_CONFIG_INCOMPLETE", "AI_MNEMONIC_LANGUAGE_INVALID"].some((code) => text.includes(code));
      await failOrRetry(job, transient, "AI_TASK_FAILED", text, Date.now());
    }
    return;
  }
  const word = await sqlite.prepare("SELECT * FROM words WHERE id = ?").get(job.wordId) as Record<string, unknown> | undefined;
  if (!word) {
    await failOrRetry(job, false, "WORD_NOT_FOUND", "词条不存在", Date.now());
    return;
  }
  const contentRow = await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(job.wordId) as Record<string, unknown> | undefined;
  const existing = dictionaryContentFromRow(contentRow);
  const requestedFields = normalizeRequestedFields(job.requestedFields);
  const sourceLanguage = String(word.source_language);
  const targetLanguage = String(word.target_language);
  const entryType = String(word.content_type ?? word.entry_type) as EntryType;
  const targetDefinitionsReady = requestedFieldStatusForLanguages(
    existing,
    ["definitions"],
    sourceLanguage,
    targetLanguage,
  ) === "READY";
  const existingContentReady = entryType === "SENTENCE"
    ? contentStatus(existing, entryType) !== "FAILED"
    : targetDefinitionsReady;

  if (job.mode === "SKIP_INITIALIZED" && existingContentReady) {
    await completeJob(job, contentStatus(existing, entryType), Date.now());
    return;
  }
  if (job.mode === "FILL_MISSING_FIELDS" && requestedFields.length
    && requestedFieldStatusForLanguages(existing, requestedFields, sourceLanguage, targetLanguage) === "READY") {
    await completeJob(job, "READY", Date.now(), contentStatus(existing, entryType));
    return;
  }

  try {
    const settings = settingsForAiAttempt(await getSettings(), job.attemptCount);
    const result = await lookupDictionary({
      term: String(word.term),
      normalizedTerm: String(word.normalized_term),
      entryType,
      sourceLanguage,
      targetLanguage,
      initializationMode: job.mode,
      requestedFields,
      requestedProviders: job.requestedProviders,
      providerStrategy: job.providerStrategy ?? "PARALLEL_MERGE",
      existingContent: existing,
    }, settings);
    const now = Date.now();
    await saveAttempts(job.id, job.wordId, result.attempts, now);
    const incomingStatus = requestedFields.length
      ? requestedFieldStatusForLanguages(result.content, requestedFields, sourceLanguage, targetLanguage)
      : contentStatus(result.content, entryType);
    if (incomingStatus === "FAILED") {
      const attemptSummary = result.attempts
        .map((a) => `${a.providerId}=${a.status}${a.errorCode ? `[${a.errorCode}]` : ""}${a.fieldsReturned.length ? `(${a.fieldsReturned.join(",")})` : ""}`)
        .join(" ");
      const detail = requestedFields.length
        ? `所选数据来源没有返回本次要求的字段。Provider 执行情况：${attemptSummary}`
        : `没有获取到可用释义。Provider 执行情况：${attemptSummary}`;
      await failOrRetry(job, result.hasTransientFailure, result.hasTransientFailure ? "PROVIDER_TRANSIENT_FAILURE" : "REQUESTED_FIELDS_EMPTY", detail, now);
      return;
    }

    const merged = requestedFields.length
      ? mergeRequestedFields(existing, result.content, requestedFields, job.mode)
      : job.mode === "FORCE_OVERWRITE"
        ? preserveUserContent(existing, result.content)
        : mergeDictionaryContent(existing, result.content);
    const taskStatus = requestedFields.length ? incomingStatus : contentStatus(merged, entryType);
    let wordStatus = contentStatus(merged, entryType);
    if (wordStatus === "FAILED" && taskStatus !== "FAILED") wordStatus = "PARTIAL";
    await saveContent(job.wordId, merged, result.attempts, result.contentSource, now);
    await completeJob(job, taskStatus, now, wordStatus);
    if (!requestedFields.length) await queueSupplementalTasks(
      job.wordId,
      merged,
      settings,
      entryType,
      sourceLanguage,
      targetLanguage,
    );
  } catch (error) {
    await failOrRetry(job, true, "WORKER_EXCEPTION", String(error), Date.now());
  }
}

export async function updateHeartbeat(workerId: string, status: "STARTING" | "IDLE" | "WORKING" | "STOPPING" | "ERROR", currentJobId?: number, metadata?: Record<string, unknown>): Promise<void> {
  const now = Date.now();
  await sqlite.prepare(`INSERT INTO worker_heartbeats(worker_id, status, current_job_id, metadata_json, last_seen_at, started_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(worker_id) DO UPDATE SET status = excluded.status, current_job_id = excluded.current_job_id,
      metadata_json = excluded.metadata_json, last_seen_at = excluded.last_seen_at`)
    .run(workerId, status, currentJobId ?? null, JSON.stringify(metadata ?? {}), now, now);
}
