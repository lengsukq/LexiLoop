import { db, sqlite } from "@/db/client";
import { initializationJobs, words, workerHeartbeats } from "@/db/schema";
import type { AiTaskType, DictionaryContent, InitializationMode, InitializationStatus, ProviderAttempt } from "@/lib/types";
import { getSettings, settingsForAiAttempt } from "@/modules/settings/service";
import { contentStatus, dictionaryContentFromRow, mergeDictionaryContent } from "@/modules/dictionary/content";
import { lookupDictionary } from "@/modules/dictionary/pipeline";
import { runSupplementalTask } from "@/modules/ai-tasks/supplemental";
import { eq, and, like, sql, count, type SQL } from "drizzle-orm";

export interface ClaimedJob {
  id: number;
  wordId: number;
  taskType: AiTaskType;
  mode: InitializationMode;
  attemptCount: number;
  maxAttempts: number;
}

function maxAttemptsFromSettings(): number {
  try {
    const row = sqlite.prepare("SELECT value_json FROM settings WHERE key = 'aiRetryCount'").get() as { value_json: string } | undefined;
    const retryCount = row ? Number(JSON.parse(row.value_json)) : 1;
    return Math.max(1, Math.min(6, (Number.isInteger(retryCount) ? retryCount : 1) + 1));
  } catch { return 2; }
}

function retryDelayMs(attemptCount: number): number {
  return [5_000, 30_000, 2 * 60_000, 10 * 60_000, 30 * 60_000][Math.max(0, attemptCount - 1)] ?? 30 * 60_000;
}

function usableContentStatus(wordId: number): InitializationStatus | null {
  const row = sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(wordId) as Record<string, unknown> | undefined;
  if (!row) return null;
  const status = contentStatus(dictionaryContentFromRow(row));
  return status === "FAILED" ? null : status;
}

function setWordOperationalStatus(wordId: number, requestedStatus: InitializationStatus, now: number): void {
  const fallback = usableContentStatus(wordId);
  sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?")
    .run(fallback ?? requestedStatus, now, wordId);
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
    const candidates = sqlite.prepare(`SELECT id, word_id, task_type, mode, attempt_count, max_attempts
      FROM initialization_jobs
      WHERE status = 'QUEUED' AND attempt_count < max_attempts
        AND (available_at IS NULL OR available_at <= ?)
      ORDER BY priority DESC, created_at ASC LIMIT ?`).all(now, limit) as Array<{
        id: number; word_id: number; task_type: AiTaskType; mode: InitializationMode; attempt_count: number; max_attempts: number;
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

function completeJob(job: ClaimedJob, status: InitializationStatus, now: number): void {
  sqlite.prepare(`UPDATE initialization_jobs SET status = ?, locked_at = NULL, locked_by = NULL,
    completed_at = ?, updated_at = ?, last_error = NULL, last_error_code = NULL WHERE id = ?`)
    .run(status, now, now, job.id);
  if (job.taskType === "INITIALIZE") sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?").run(status, now, job.wordId);
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

  if (job.mode === "SKIP_INITIALIZED" && existing.definitions.length > 0) {
    completeJob(job, contentStatus(existing), Date.now());
    return;
  }

  try {
    const settings = settingsForAiAttempt(await getSettings(), job.attemptCount);
    const result = await lookupDictionary({
      term: String(word.term),
      normalizedTerm: String(word.normalized_term),
      entryType: String(word.content_type ?? word.entry_type) as import("@/lib/types").EntryType,
      sourceLanguage: String(word.source_language),
      targetLanguage: String(word.target_language),
      initializationMode: job.mode,
      existingContent: existing,
    }, settings);
    const now = Date.now();
    saveAttempts(job.id, job.wordId, result.attempts, now);
    if (result.requiredProviderFailure) {
      failOrRetry(
        job,
        result.requiredProviderFailure.transient,
        result.requiredProviderFailure.errorCode,
        result.requiredProviderFailure.errorMessage,
        now,
      );
      return;
    }
    const merged = job.mode === "FORCE_OVERWRITE"
      ? preserveUserContent(existing, result.content)
      : mergeDictionaryContent(existing, result.content);
    const status = contentStatus(merged);
    if (status === "FAILED") {
      failOrRetry(job, result.hasTransientFailure, result.hasTransientFailure ? "PROVIDER_TRANSIENT_FAILURE" : "NO_DEFINITION", "没有获取到可用释义", now);
      return;
    }
    saveContent(job.wordId, merged, result.attempts, result.contentSource, now);
    completeJob(job, status, now);
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

export function queueWordInitialization(wordId: number, mode: InitializationMode = "FILL_MISSING_FIELDS", priority = 100): number {
  return queueAiTask(wordId, "INITIALIZE", mode, priority);
}

export function queueAiTask(
  wordId: number,
  taskType: AiTaskType,
  mode: InitializationMode = "FILL_MISSING_FIELDS",
  priority = 100,
): number {
  const word = sqlite.prepare("SELECT id FROM words WHERE id = ?").get(wordId);
  if (!word) throw new Error("WORD_NOT_FOUND");
  const now = Date.now();
  const maxAttempts = maxAttemptsFromSettings();
  const active = sqlite.prepare("SELECT id, mode FROM initialization_jobs WHERE word_id = ? AND task_type = ? AND status IN ('QUEUED','RUNNING') LIMIT 1").get(wordId, taskType) as { id: number; mode: InitializationMode } | undefined;
  if (active) {
    sqlite.prepare("UPDATE initialization_jobs SET mode = ?, priority = MAX(priority, ?), max_attempts = MAX(max_attempts, ?), available_at = ?, updated_at = ? WHERE id = ?")
      .run(strongerInitializationMode(active.mode, mode), priority, maxAttempts, now, now, active.id);
    return active.id;
  }
  const result = sqlite.prepare(`INSERT INTO initialization_jobs
    (word_id, task_type, mode, requested_fields_json, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
    VALUES (?, ?, ?, ?, 'QUEUED', ?, 0, ?, ?, ?, ?)`)
    .run(wordId, taskType, mode, taskType === "MNEMONIC" ? '["learning.mnemonic"]' : taskType === "EXAMPLE_TRANSLATIONS" ? '["examples.translation"]' : null, priority, maxAttempts, now, now, now);
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

/**
 * Queue a deliberate selection from the wordbook or task list.  A selection is
 * intentionally not filtered by previous AI attempts: a word may have AI
 * content already, while still missing an example, mnemonic, or morphology.
 */
export function queueSelectedInitialization(
  wordIds: number[],
  mode: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE"> = "FILL_MISSING_FIELDS",
): QueueInitializationResult {
  const requestedIds = [...new Set(wordIds.filter((id) => Number.isInteger(id) && id > 0))];
  if (!requestedIds.length) return { requestedWords: 0, selectedWords: 0, skippedWords: 0, createdJobs: 0, updatedJobs: 0, mode };

  const placeholders = requestedIds.map(() => "?").join(", ");
  const existingIds = new Set((sqlite.prepare(`SELECT id FROM words WHERE id IN (${placeholders})`).all(...requestedIds) as Array<{ id: number }>)
    .map((row) => row.id));
  const now = Date.now();
  let createdJobs = 0;
  let updatedJobs = 0;

  sqlite.transaction(() => {
    const findActive = sqlite.prepare(`SELECT id, mode FROM initialization_jobs
      WHERE word_id = ? AND task_type = 'INITIALIZE' AND status IN ('QUEUED','RUNNING') LIMIT 1`);
    const updateActive = sqlite.prepare(`UPDATE initialization_jobs
      SET mode = ?, priority = MAX(priority, 90), available_at = ?, updated_at = ? WHERE id = ?`);
    const insertJob = sqlite.prepare(`INSERT INTO initialization_jobs
      (word_id, task_type, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
      VALUES (?, 'INITIALIZE', ?, 'QUEUED', 90, 0, ?, ?, ?, ?)`);
    for (const wordId of existingIds) {
      const active = findActive.get(wordId) as { id: number; mode: InitializationMode } | undefined;
      if (active) {
        updateActive.run(strongerInitializationMode(active.mode, mode), now, now, active.id);
        updatedJobs += 1;
      } else {
        insertJob.run(wordId, mode, maxAttemptsFromSettings(), now, now, now);
        createdJobs += 1;
      }
      setWordOperationalStatus(wordId, "QUEUED", now);
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
) {
  const total = (sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count: number }).count;
  const aiFilter = onlyWithoutAi
    ? `WHERE NOT EXISTS (
        SELECT 1 FROM provider_attempts pa
        WHERE pa.word_id = w.id AND pa.provider_id LIKE 'ai:%' AND pa.status = 'SUCCESS'
      )`
    : "";
  const candidates = sqlite.prepare(`SELECT w.id FROM words w ${aiFilter} ORDER BY w.id ASC`).all() as Array<{ id: number }>;
  const queued = queueSelectedInitialization(candidates.map((candidate) => candidate.id), mode);
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

export async function getInitializationSummary() {
  const counts = await db.select({ status: initializationJobs.status, count: sql<number>`count(*)` }).from(initializationJobs).groupBy(initializationJobs.status);
  const result: Record<InitializationStatus, number> = { PENDING: 0, QUEUED: 0, RUNNING: 0, READY: 0, PARTIAL: 0, FAILED: 0, DISABLED: 0 };
  for (const row of counts) result[row.status] = Number(row.count);
  return result;
}

export async function getWordsSummary() {
  const counts = await db.select({ status: words.initializationStatus, count: sql<number>`count(*)` }).from(words).groupBy(words.initializationStatus);
  const result: Record<InitializationStatus, number> = { PENDING: 0, QUEUED: 0, RUNNING: 0, READY: 0, PARTIAL: 0, FAILED: 0, DISABLED: 0 };
  for (const row of counts) result[row.status] = Number(row.count);
  return result;
}

export async function listInitializationJobs(options: { page?: number; pageSize?: number; status?: InitializationStatus; search?: string } = {}) {
  const { page = 1, pageSize = 50, status: statusFilter, search } = options;
  const conditions: SQL[] = [];
  if (statusFilter) conditions.push(eq(initializationJobs.status, statusFilter));
  if (search) conditions.push(like(words.term, `%${search}%`));
  const where = conditions.length > 0 ? and(...conditions) : sql`1=1`;

  const base = db.select({
    id: initializationJobs.id, wordId: initializationJobs.wordId, term: words.term, taskType: initializationJobs.taskType,
    status: initializationJobs.status, mode: initializationJobs.mode, priority: initializationJobs.priority,
    attemptCount: initializationJobs.attemptCount, maxAttempts: initializationJobs.maxAttempts,
    lastError: initializationJobs.lastError, lastErrorCode: initializationJobs.lastErrorCode,
    createdAt: initializationJobs.createdAt, updatedAt: initializationJobs.updatedAt, completedAt: initializationJobs.completedAt,
  }).from(initializationJobs).innerJoin(words, eq(initializationJobs.wordId, words.id));

  const countResult = await db.select({ total: count() }).from(initializationJobs)
    .innerJoin(words, eq(initializationJobs.wordId, words.id))
    .where(where);
  const total = Number(countResult[0]?.total ?? 0);

  const jobs = await base.where(where).orderBy(sql`${initializationJobs.createdAt} DESC`).limit(pageSize).offset((page - 1) * pageSize);
  return { jobs, total };
}

export async function getJobDetails(jobId: number) {
  const rows = sqlite.prepare(`
    SELECT j.*, w.term, w.normalized_term, w.source_language, w.target_language
    FROM initialization_jobs j
    JOIN words w ON w.id = j.word_id
    WHERE j.id = ?
  `).get(jobId) as Record<string, unknown> | undefined;
  if (!rows) return null;

  const attempts = sqlite.prepare(`
    SELECT * FROM provider_attempts WHERE initialization_job_id = ? ORDER BY created_at ASC
  `).all(jobId) as Array<Record<string, unknown>>;

  const wordContent = sqlite.prepare(`
    SELECT * FROM word_contents WHERE word_id = ?
  `).get(rows.word_id as number) as Record<string, unknown> | undefined;

  const contentFieldKeys = [
    "definitions", "pronunciations", "examples", "phrases", "forms",
    "synonyms", "antonyms", "wordFamily", "confusedWords", "roots", "affixes",
    "tags",
  ] as const;

  const contentFields = wordContent
    ? Object.fromEntries(contentFieldKeys.map((key) => {
        const col = `${key.replace(/[A-Z]/g, (c) => `_${c.toLowerCase()}`)}_json` as string;
        const arr: unknown[] = JSON.parse((wordContent[col] as string) || "[]");
        return [key, arr.length > 0];
      }))
    : Object.fromEntries(contentFieldKeys.map((key) => [key, false]));

  // Check summary sub-fields
  const summaryJson = wordContent?.summary_json as string | undefined;
  const summary = summaryJson ? JSON.parse(summaryJson) : null;
  contentFields.summary = summary && (summary.shortDefinition || summary.translation);
  contentFields.learning = summary && (summary.pronunciationTip || (summary.mnemonic));
  // Re-check learning from learning_json
  const learningJson = wordContent?.learning_json as string | undefined;
  const learning = learningJson ? JSON.parse(learningJson) : null;
  contentFields.learning = learning && (learning.pronunciationTip || learning.mnemonic || learning.commonMistakes?.length > 0);
  // sentenceAnalysis
  const saJson = wordContent?.sentence_analysis_json as string | undefined;
  const sa = saJson ? JSON.parse(saJson) : null;
  contentFields.sentenceAnalysis = sa && (sa.grammarNotes?.length > 0 || sa.keyExpressions?.length > 0);

  const formatAttempt = (a: Record<string, unknown>) => ({
    id: a.id as number,
    providerId: a.provider_id as string,
    status: a.status as string,
    durationMs: a.duration_ms as number,
    fieldsReturned: JSON.parse((a.fields_returned_json as string) || "[]") as string[],
    errorCode: a.error_code as string | null,
    errorMessage: a.error_message as string | null,
    metadata: a.metadata_json ? JSON.parse(a.metadata_json as string) : null,
    createdAt: a.created_at as number,
  });

  return {
    job: {
      id: rows.id as number,
      wordId: rows.word_id as number,
      taskType: rows.task_type as AiTaskType,
      term: rows.term as string,
      normalizedTerm: rows.normalized_term as string,
      sourceLanguage: rows.source_language as string,
      targetLanguage: rows.target_language as string,
      status: rows.status as string,
      mode: rows.mode as string,
      priority: rows.priority as number,
      attemptCount: rows.attempt_count as number,
      maxAttempts: rows.max_attempts as number,
      lastError: rows.last_error as string | null,
      lastErrorCode: rows.last_error_code as string | null,
      availableAt: rows.available_at as number | null,
      lockedAt: rows.locked_at as number | null,
      lockedBy: rows.locked_by as string | null,
      createdAt: rows.created_at as number,
      updatedAt: rows.updated_at as number,
      completedAt: rows.completed_at as number | null,
    },
    attempts: attempts.map(formatAttempt),
    contentFields,
  };
}

export async function getWorkerHeartbeats() {
  return db.select().from(workerHeartbeats).orderBy(sql`${workerHeartbeats.lastSeenAt} DESC`);
}
