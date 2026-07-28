import { db, sqlite } from "@/db/client";
import { initializationJobs, words, workerHeartbeats } from "@/db/schema";
import type {
  AiTaskType,
  InitializationField,
  InitializationProviderId,
  InitializationStatus,
  ProviderStrategy,
} from "@/lib/types";
import { PROVIDER_CAPABILITIES } from "@/modules/dictionary/pipeline";
import { getEcdictStatus } from "@/modules/ecdict/service";
import { getSettings } from "@/modules/settings/service";
import { and, count, eq, like, sql, type SQL } from "drizzle-orm";
import { parseStringArray } from "./shared";
export async function getInitializationOptions() {
  const [settings, ecdict] = await Promise.all([getSettings(), getEcdictStatus()]);
  const aiPurpose = settings.llmConfig.purposes.IMPORT_ENRICHMENT;
  const aiProvider = settings.llmConfig.providers.find((provider) => provider.id === aiPurpose.providerId);
  const mwDictionaryReady = Boolean(settings.merriamWebsterDictionaryKey.trim());
  const mwThesaurusReady = Boolean(settings.merriamWebsterThesaurusKey.trim());
  const providers: Array<{
    id: InitializationProviderId;
    label: string;
    available: boolean;
    enabled: boolean;
    reason: string | null;
    capabilities: InitializationField[];
  }> = [
    {
      id: "merriam-webster",
      label: "Merriam-Webster",
      enabled: settings.merriamWebsterEnabled,
      available: settings.merriamWebsterEnabled && (mwDictionaryReady || mwThesaurusReady),
      reason: !settings.merriamWebsterEnabled ? "请先在设置中启用" : !mwDictionaryReady && !mwThesaurusReady ? "尚未配置 API Key" : null,
      capabilities: [
        ...(mwDictionaryReady ? PROVIDER_CAPABILITIES["merriam-webster"].filter((field) => !["synonyms", "antonyms"].includes(field)) : []),
        ...(mwThesaurusReady ? (["synonyms", "antonyms"] as InitializationField[]) : []),
      ],
    },
    {
      id: "dictionaryapi.dev",
      label: "DictionaryAPI.dev",
      enabled: settings.dictionaryApiEnabled,
      available: settings.dictionaryApiEnabled,
      reason: settings.dictionaryApiEnabled ? null : "请先在设置中启用",
      capabilities: PROVIDER_CAPABILITIES["dictionaryapi.dev"],
    },
    {
      id: "ecdict",
      label: "ECDICT",
      enabled: settings.ecdictEnabled,
      available: ecdict.installed && settings.ecdictEnabled,
      reason: !ecdict.installed ? "尚未安装离线词典" : !settings.ecdictEnabled ? "词典当前已停用" : null,
      capabilities: PROVIDER_CAPABILITIES.ecdict,
    },
    {
      id: "ai",
      label: "AI 词条初始化",
      enabled: aiPurpose.enabled,
      available: Boolean(aiPurpose.enabled && aiProvider?.apiKey.trim() && aiProvider.baseUrl.trim() && aiPurpose.model.trim()),
      reason: !aiPurpose.enabled ? "AI 词条初始化未启用" : !aiProvider ? "AI Provider 不存在" : !aiProvider.apiKey.trim() || !aiProvider.baseUrl.trim() || !aiPurpose.model.trim() ? "AI 配置不完整" : null,
      capabilities: PROVIDER_CAPABILITIES.ai,
    },
    {
      id: "mymemory",
      label: "MyMemory 翻译",
      enabled: settings.myMemoryEnabled,
      available: settings.myMemoryEnabled,
      reason: settings.myMemoryEnabled ? null : "请先在设置中启用",
      capabilities: PROVIDER_CAPABILITIES.mymemory,
    },
    {
      id: "tencent-translate",
      label: "腾讯翻译",
      enabled: settings.tencentTranslateEnabled,
      available: settings.tencentTranslateEnabled && Boolean(settings.tencentTranslateSecretId.trim()) && Boolean(settings.tencentTranslateSecretKey.trim()),
      reason: !settings.tencentTranslateEnabled ? "请先在设置中启用" : !settings.tencentTranslateSecretId.trim() || !settings.tencentTranslateSecretKey.trim() ? "尚未配置 API 密钥" : null,
      capabilities: PROVIDER_CAPABILITIES["tencent-translate"],
    },
  ];
  return { providers };
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
    requestedFields: initializationJobs.requestedFieldsJson, requestedProviders: initializationJobs.requestedProvidersJson,
    providerStrategy: initializationJobs.providerStrategy,
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
      requestedFields: parseStringArray<InitializationField>(rows.requested_fields_json),
      requestedProviders: parseStringArray<InitializationProviderId>(rows.requested_providers_json),
      providerStrategy: (rows.provider_strategy as ProviderStrategy | null) ?? "PARALLEL_MERGE",
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
