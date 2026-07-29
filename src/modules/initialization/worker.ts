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
import { parseStringArray, setWordOperationalStatus } from "./shared";
import { queueAiTask } from "./queue";
import type { ClaimedJob } from "./types";

export type { ClaimedJob } from "./types";

function retryDelayMs(attemptCount: number): number {
  return [5_000, 30_000, 2 * 60_000, 10 * 60_000, 30 * 60_000][Math.max(0, attemptCount - 1)]
    ?? 30 * 60_000;
}

function preserveUserContent(existing: DictionaryContent, refreshed: DictionaryContent): DictionaryContent {
  return mergeDictionaryContent({
    definitions: existing.definitions.filter((item) => item.isUserEdited),
    examples: existing.examples.filter((item) => item.isUserAdded),
  }, refreshed);
}
export function recoverStaleJobs(staleAfterMs = 10 * 60_000): number {
  const now = Date.now();
  const result = sqlite.prepare(`UPDATE initialization_jobs
    SET status = 'QUEUED', locked_at = NULL, locked_by = NULL, available_at = ?,
        last_error = COALESCE(last_error, 'Worker lock expired'), last_error_code = 'STALE_LOCK', updated_at = ?
    WHERE status = 'RUNNING' AND locked_at IS NOT NULL AND locked_at < ?`)
    .run(now, now, now - staleAfterMs);
  const queuedWords = sqlite.prepare("SELECT DISTINCT word_id FROM initialization_jobs WHERE status = 'QUEUED' AND task_type = 'INITIALIZE'").all() as Array<{ word_id: number }>;
  for (const job of queuedWords) setWordOperationalStatus(job.word_id, "QUEUED", now);
  return result.changes;
}

export function claimJobs(workerId: string, limit: number): ClaimedJob[] {
  const now = Date.now();
  recoverStaleJobs();
  return sqlite.transaction(() => {
    const candidates = sqlite.prepare(`SELECT id, word_id, task_type, mode, attempt_count, max_attempts,
        requested_fields_json, requested_providers_json, provider_strategy
      FROM initialization_jobs
      WHERE status = 'QUEUED' AND attempt_count < max_attempts
        AND (available_at IS NULL OR available_at <= ?)
      ORDER BY priority DESC, created_at ASC LIMIT ?`).all(now, limit) as Array<{
        id: number; word_id: number; task_type: AiTaskType; mode: InitializationMode; attempt_count: number; max_attempts: number;
        requested_fields_json: string | null; requested_providers_json: string | null; provider_strategy: ProviderStrategy | null;
      }>;
    const claimed: ClaimedJob[] = [];
    const claim = sqlite.prepare(`UPDATE initialization_jobs SET status = 'RUNNING', locked_at = ?, locked_by = ?,
      attempt_count = attempt_count + 1, updated_at = ? WHERE id = ? AND status = 'QUEUED'`);
    for (const candidate of candidates) {
      const result = claim.run(now, workerId, now, candidate.id);
      if (result.changes !== 1) continue;
      if (candidate.task_type === "INITIALIZE") setWordOperationalStatus(candidate.word_id, "RUNNING", now);
      claimed.push({
        id: candidate.id,
        wordId: candidate.word_id,
        taskType: candidate.task_type,
        mode: candidate.mode,
        attemptCount: candidate.attempt_count + 1,
        maxAttempts: candidate.max_attempts,
        requestedFields: parseStringArray<InitializationField>(candidate.requested_fields_json),
        requestedProviders: parseStringArray<InitializationProviderId>(candidate.requested_providers_json),
        providerStrategy: candidate.provider_strategy ?? "PARALLEL_MERGE",
      });
    }
    return claimed;
  }).immediate();
}

function saveAttempts(jobId: number, wordId: number, attempts: ProviderAttempt[], now: number): void {
  const insert = sqlite.prepare(`INSERT INTO provider_attempts
    (initialization_job_id, word_id, provider_id, status, duration_ms, fields_returned_json, error_code, error_message, metadata_json, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`);
  for (const attempt of attempts) {
    insert.run(jobId, wordId, attempt.providerId, attempt.status, attempt.durationMs, JSON.stringify(attempt.fieldsReturned), attempt.errorCode ?? null, attempt.errorMessage ?? null, attempt.metadata ? JSON.stringify(attempt.metadata) : null, now);
  }
}

function saveContent(wordId: number, content: DictionaryContent, attempts: ProviderAttempt[], contentSource: string, now: number): void {
  sqlite.prepare(`INSERT INTO word_contents
    (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
     synonyms_json, antonyms_json, word_family_json, confused_words_json, roots_json, affixes_json,
     summary_json, learning_json, sentence_analysis_json, tags_json, provider_metadata_json, content_source, content_version, initialized_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
    ON CONFLICT(word_id) DO UPDATE SET
      definitions_json = excluded.definitions_json,
      pronunciations_json = excluded.pronunciations_json,
      examples_json = excluded.examples_json,
      phrases_json = excluded.phrases_json,
      forms_json = excluded.forms_json,
      synonyms_json = excluded.synonyms_json,
      antonyms_json = excluded.antonyms_json,
      word_family_json = excluded.word_family_json,
      confused_words_json = excluded.confused_words_json,
      roots_json = excluded.roots_json,
      affixes_json = excluded.affixes_json,
      summary_json = excluded.summary_json,
      learning_json = excluded.learning_json,
      sentence_analysis_json = excluded.sentence_analysis_json,
      tags_json = excluded.tags_json,
      provider_metadata_json = excluded.provider_metadata_json,
      content_source = excluded.content_source,
      content_version = word_contents.content_version + 1,
      initialized_at = excluded.initialized_at,
      updated_at = excluded.updated_at`)
    .run(
      wordId,
      JSON.stringify(content.definitions), JSON.stringify(content.pronunciations), JSON.stringify(content.examples),
      JSON.stringify(content.phrases), JSON.stringify(content.forms), JSON.stringify(content.synonyms),
      JSON.stringify(content.antonyms), JSON.stringify(content.wordFamily), JSON.stringify(content.confusedWords),
      JSON.stringify(content.roots), JSON.stringify(content.affixes), JSON.stringify(content.summary),
      JSON.stringify(content.learning), JSON.stringify(content.sentenceAnalysis), JSON.stringify(content.tags), JSON.stringify(attempts), contentSource, now, now,
    );
}

function completeJob(job: ClaimedJob, status: InitializationStatus, now: number, wordStatus: InitializationStatus = status): void {
  sqlite.prepare(`UPDATE initialization_jobs SET status = ?, locked_at = NULL, locked_by = NULL,
    completed_at = ?, updated_at = ?, last_error = NULL, last_error_code = NULL WHERE id = ?`)
    .run(status, now, now, job.id);
  if (job.taskType === "INITIALIZE") sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?").run(wordStatus, now, job.wordId);
}

/** 初始化成功后排队非事实内容；低优先级执行，不阻塞词典内容落库。 */
function queueSupplementalTasks(
  wordId: number,
  content: DictionaryContent,
  settings: AppSettings,
  entryType: EntryType,
  sourceLanguage: string,
  targetLanguage: string,
): void {
  const purpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  const provider = settings.llmConfig.providers.find((item) => item.id === purpose.providerId);
  if (!purpose.enabled || !provider || !provider.apiKey.trim() || !provider.baseUrl.trim() || !purpose.model.trim()) return;

  if (entryType === "SENTENCE") {
    const hasTargetTranslation = content.definitions.some((item) => item.language === targetLanguage && item.text.trim())
      || Boolean(content.summary.translation?.trim());
    if (!hasTargetTranslation) queueAiTask(wordId, "EXAMPLE_TRANSLATIONS", "FILL_MISSING_FIELDS", 20);
    return;
  }

  if (sourceLanguage.startsWith("en") && !content.learning.mnemonic?.trim()) {
    queueAiTask(wordId, "MNEMONIC", "FILL_MISSING_FIELDS", 20);
  }
}

function failOrRetry(job: ClaimedJob, transient: boolean, errorCode: string, errorMessage: string, now: number): void {
  if (transient && job.attemptCount < job.maxAttempts) {
    sqlite.prepare(`UPDATE initialization_jobs SET status = 'QUEUED', locked_at = NULL, locked_by = NULL,
      available_at = ?, last_error = ?, last_error_code = ?, updated_at = ? WHERE id = ?`)
      .run(now + retryDelayMs(job.attemptCount), errorMessage, errorCode, now, job.id);
    if (job.taskType === "INITIALIZE") setWordOperationalStatus(job.wordId, "QUEUED", now);
    return;
  }
  sqlite.prepare(`UPDATE initialization_jobs SET status = 'FAILED', locked_at = NULL, locked_by = NULL,
    completed_at = ?, last_error = ?, last_error_code = ?, updated_at = ? WHERE id = ?`)
    .run(now, errorMessage, errorCode, now, job.id);
  if (job.taskType === "INITIALIZE") setWordOperationalStatus(job.wordId, "FAILED", now);
}

export async function processJob(job: ClaimedJob): Promise<void> {
  if (job.taskType !== "INITIALIZE") {
    try {
      await runSupplementalTask(job.taskType, job.wordId, job.attemptCount);
      completeJob(job, "READY", Date.now());
    } catch (error) {
      const text = String(error);
      const transient = !["WORD_NOT_FOUND", "AI_DISABLED", "AI_CONFIG_INCOMPLETE", "AI_MNEMONIC_LANGUAGE_INVALID"].some((code) => text.includes(code));
      failOrRetry(job, transient, "AI_TASK_FAILED", text, Date.now());
    }
    return;
  }
  const word = sqlite.prepare("SELECT * FROM words WHERE id = ?").get(job.wordId) as Record<string, unknown> | undefined;
  if (!word) {
    failOrRetry(job, false, "WORD_NOT_FOUND", "词条不存在", Date.now());
    return;
  }
  const contentRow = sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(job.wordId) as Record<string, unknown> | undefined;
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
    completeJob(job, contentStatus(existing, entryType), Date.now());
    return;
  }
  if (job.mode === "FILL_MISSING_FIELDS" && requestedFields.length
    && requestedFieldStatusForLanguages(existing, requestedFields, sourceLanguage, targetLanguage) === "READY") {
    completeJob(job, "READY", Date.now(), contentStatus(existing, entryType));
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
    saveAttempts(job.id, job.wordId, result.attempts, now);
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
      failOrRetry(job, result.hasTransientFailure, result.hasTransientFailure ? "PROVIDER_TRANSIENT_FAILURE" : "REQUESTED_FIELDS_EMPTY", detail, now);
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
    saveContent(job.wordId, merged, result.attempts, result.contentSource, now);
    completeJob(job, taskStatus, now, wordStatus);
    if (!requestedFields.length) queueSupplementalTasks(
      job.wordId,
      merged,
      settings,
      entryType,
      sourceLanguage,
      targetLanguage,
    );
  } catch (error) {
    failOrRetry(job, true, "WORKER_EXCEPTION", String(error), Date.now());
  }
}

export function updateHeartbeat(workerId: string, status: "STARTING" | "IDLE" | "WORKING" | "STOPPING" | "ERROR", currentJobId?: number, metadata?: Record<string, unknown>): void {
  const now = Date.now();
  sqlite.prepare(`INSERT INTO worker_heartbeats(worker_id, status, current_job_id, metadata_json, last_seen_at, started_at)
    VALUES (?, ?, ?, ?, ?, ?)
    ON CONFLICT(worker_id) DO UPDATE SET status = excluded.status, current_job_id = excluded.current_job_id,
      metadata_json = excluded.metadata_json, last_seen_at = excluded.last_seen_at`)
    .run(workerId, status, currentJobId ?? null, JSON.stringify(metadata ?? {}), now, now);
}
