import { z } from "zod";
import {
  ApiError,
  parsePositiveInt,
  requireRouteId,
  resolveFailPayload,
  resolveRouteError,
} from "@/lib/api-errors";
import {
  articleMergeSchema,
  articlePreviewSchema,
  gameSessionCompleteSchema,
  gameSessionStartSchema,
  importCommitSchema,
  initializationBulkSchema,
  initializationPreviewSchema,
  initializationRetrySchema,
  matchSessionCompleteSchema,
  matchSessionStartSchema,
  phoneticsSessionCompleteSchema,
  phoneticsSessionStartSchema,
  reviewPreviewSchema,
  studyAnswerSchema,
  studySessionStartSchema,
  studySkipSchema,
  wordExampleTranslationIndexSchema,
  wordInitializeSchema,
  wordYoudaoApplySchema,
  wordYoudaoPreviewSchema,
} from "@/lib/route-schemas";
import {
  INITIALIZATION_STATUSES,
  MASTERY_LEVELS,
  type InitializationStatus,
  type MasteryLevel,
  type ProviderAttempt,
} from "@/lib/types";
import { ensureBrowserDbReady } from "@/local/browser-db-client";
import { generateChineseMnemonic } from "@/modules/ai-tasks/supplemental";
import { commitArticleImport } from "@/modules/article-import/commit";
import { createArticlePreview, mergeArticlePreviews } from "@/modules/article-import/service";
import { runBackgroundTick } from "@/modules/background/tick";
import {
  extractBackupRawFromFormData,
  extractBackupRawFromJson,
  restoreBackupWithSummary,
} from "@/modules/backups/restore-request";
import { createJsonBackup } from "@/modules/backups/service";
import { normalizeDictionaryContent } from "@/modules/dictionary/content";
import { completeGameSession, startGameSession } from "@/modules/games/service";
import { getHealthSnapshot } from "@/modules/health/service";
import { createImportPreviewFromFile } from "@/modules/imports/preview-file";
import {
  commitImport,
  ImportRollbackError,
  listImportBatches,
  rollbackImportBatch,
} from "@/modules/imports/service";
import {
  getInitializationOptions,
  getInitializationSummary,
  getJobDetails,
  getWordsSummary,
  getWorkerHeartbeats,
  listInitializationJobs,
  previewConfiguredInitialization,
  queueAiTask,
  queueBulkInitialization,
  queueConfiguredInitialization,
  queueSelectedInitialization,
  queueWordInitialization,
  retryFailedJobs,
  retryFailedJobsForWords,
} from "@/modules/initialization/service";
import { confirmManualPreview, createManualPreview, ManualPreviewError } from "@/modules/manual/service";
import { completeMatchingSession, startMatchingSession } from "@/modules/matching/service";
import { completePhoneticGame, startPhoneticGame } from "@/modules/phonetics/service";
import { getReviewPreview, processReviewAnswer } from "@/modules/reviews/service";
import { getSettings, updateSettings } from "@/modules/settings/service";
import { getDashboard, getStatistics } from "@/modules/statistics/service";
import { getDailyStudyPlan, getStudySession, skipStudyItem, startStudySession } from "@/modules/study/service";
import { getTodaySuggestion } from "@/modules/suggestions/service";
import { ensureServerSyncState } from "@/modules/sync/server-state";
import { CLOUD_SYNC_PROTOCOL_VERSION } from "@/modules/sync/types";
import { translateExample } from "@/modules/translations/service";
import {
  addRelatedWord,
  deleteExample,
  deleteWord,
  getWordDetail,
  listWords,
  previewRelatedWord,
  updateManualDefinition,
  updateWord,
} from "@/modules/words/service";
import { applyYoudaoContent, previewYoudaoContent } from "@/modules/words/youdao-refresh";

export interface LocalEnvelopeResult<T = unknown> {
  status: number;
  body:
    | { success: true; data: T }
    | { success: false; error: { code: string; message: string; details?: unknown } };
}

interface RouteMeta {
  fallbackMessage: string;
  validationMessage?: string;
}

let dbTurnQueue: Promise<void> = Promise.resolve();
let keepaliveInFlight = false;

/**
 * Serializes local database request turns so concurrent React `Promise.all`
 * loads or background keepalive polls never race on PGlite's single connection.
 */
function enqueueLocalTurn<T>(fn: () => Promise<T>): Promise<T> {
  const prev = dbTurnQueue;
  let release!: () => void;
  dbTurnQueue = new Promise<void>((resolve) => {
    release = resolve;
  });
  return prev.then(async () => {
    try {
      return await fn();
    } finally {
      release();
    }
  });
}

async function readJsonBody<T = unknown>(init?: RequestInit, fallbackEmpty = false): Promise<T> {
  if (!init?.body) {
    if (fallbackEmpty) return {} as T;
    throw new ApiError("VALIDATION_ERROR", "请求体不能为空。", 400);
  }
  if (typeof init.body === "string") {
    if (!init.body.trim()) {
      return (fallbackEmpty ? {} : undefined) as T;
    }
    return JSON.parse(init.body) as T;
  }
  if (init.body instanceof Uint8Array || init.body instanceof ArrayBuffer) {
    const text = new TextDecoder().decode(init.body);
    return (text.trim() ? JSON.parse(text) : fallbackEmpty ? {} : undefined) as T;
  }
  return init.body as unknown as T;
}

async function readJsonOptional(init?: RequestInit): Promise<unknown> {
  try {
    return await readJsonBody(init, true);
  } catch {
    return {};
  }
}

function readFormData(init?: RequestInit): FormData {
  if (init?.body instanceof FormData) return init.body;
  throw new ApiError("VALIDATION_ERROR", "请以 FormData 格式上传文件。", 400);
}

function wrapError(error: unknown, meta: RouteMeta): LocalEnvelopeResult<never> {
  if (error instanceof ManualPreviewError) {
    const status =
      error.code === "MANUAL_PREVIEW_NOT_FOUND"
        ? 404
        : error.code === "MANUAL_PREVIEW_EXPIRED"
          ? 410
          : error.code === "DICTIONARY_PREVIEW_EMPTY"
            ? 422
            : 409;
    return { status, body: resolveFailPayload(error.code, error.message, status, error.details).body };
  }
  if (error instanceof ImportRollbackError) {
    const status = error.code === "IMPORT_BATCH_NOT_FOUND" ? 404 : 409;
    return { status, body: resolveFailPayload(error.code, error.message, status, error.details).body };
  }
  return resolveRouteError(error, meta);
}

async function routeLocalRequest(url: URL, init?: RequestInit): Promise<{ status: number; data: unknown; meta?: RouteMeta }> {
  const method = (init?.method ?? "GET").toUpperCase();
  const path = url.pathname;
  const params = url.searchParams;

  // ---- Health & Analytics ----
  if (path === "/api/health" && method === "GET") {
    const health = await getHealthSnapshot();
    return { status: health.database === "error" ? 503 : 200, data: health };
  }
  if (path === "/api/dashboard" && method === "GET") {
    return { status: 200, data: await getDashboard(), meta: { fallbackMessage: "获取首页数据失败。" } };
  }
  if (path === "/api/statistics" && method === "GET") {
    return {
      status: 200,
      data: await getStatistics(parsePositiveInt(params.get("days"), 30, 365)),
      meta: { fallbackMessage: "获取学习统计失败。" },
    };
  }
  if (path === "/api/suggestions/today") {
    if (method === "GET") return { status: 200, data: await getTodaySuggestion(), meta: { fallbackMessage: "生成今日学习建议失败。" } };
    if (method === "POST") return { status: 200, data: await getTodaySuggestion({ force: true }), meta: { fallbackMessage: "重新生成今日学习建议失败。" } };
  }

  // ---- Settings ----
  if (path === "/api/settings") {
    if (method === "GET") return { status: 200, data: await getSettings(), meta: { fallbackMessage: "获取设置失败。" } };
    if (method === "PUT") {
      try {
        return { status: 200, data: await updateSettings(await readJsonBody(init)) };
      } catch (error) {
        if (error instanceof z.ZodError) throw new ApiError("VALIDATION_ERROR", "设置参数无效。", 400, error.issues);
        throw error;
      }
    }
  }

  // ---- Words Collection ----
  if (path === "/api/words" && method === "GET") {
    const rawStatus = params.get("status");
    const rawMastery = params.get("mastery");
    const rawSort = params.get("sort");
    const rawOrder = params.get("order");
    return {
      status: 200,
      data: await listWords({
        query: params.get("q")?.trim() || undefined,
        status: rawStatus && INITIALIZATION_STATUSES.includes(rawStatus as InitializationStatus) ? (rawStatus as InitializationStatus) : undefined,
        mastery: rawMastery && MASTERY_LEVELS.includes(rawMastery as MasteryLevel) ? (rawMastery as MasteryLevel) : undefined,
        wrong: params.get("wrong") === "true",
        due: params.get("due") === "true",
        suspended: params.has("suspended") ? params.get("suspended") === "true" : undefined,
        page: parsePositiveInt(params.get("page"), 1, 100_000),
        limit: parsePositiveInt(params.get("limit"), 50, 200),
        sort: ["createdAt", "term", "masteryScore", "sourceCreatedAt", "dueAt"].includes(rawSort ?? "")
          ? (rawSort as "createdAt" | "term" | "masteryScore" | "sourceCreatedAt" | "dueAt")
          : "createdAt",
        order: rawOrder === "asc" ? "asc" : "desc",
      }),
      meta: { fallbackMessage: "获取词条列表失败。" },
    };
  }

  // ---- Word Item Routes (/api/words/:id/...) ----
  const wordSubMatch = /^\/api\/words\/([^/]+)(?:\/([^/]+))?$/.exec(path);
  if (wordSubMatch) {
    const id = requireRouteId(wordSubMatch[1], "WORD_ID_INVALID", "词条 ID 无效。");
    const sub = wordSubMatch[2];

    if (!sub) {
      if (method === "GET") {
        const word = await getWordDetail(id);
        if (!word) throw new ApiError("WORD_NOT_FOUND", "词条不存在。", 404);
        return { status: 200, data: word };
      }
      if (method === "PATCH") {
        return { status: 200, data: await updateWord(id, await readJsonBody(init)) };
      }
      if (method === "DELETE") {
        const force = params.get("force") === "true";
        const deleted = await deleteWord(id, force);
        if (!deleted) throw new ApiError("WORD_NOT_FOUND", "词条不存在。", 404);
        return { status: 200, data: { deleted: true } };
      }
    } else if (sub === "content" && method === "PUT") {
      return { status: 200, data: await updateManualDefinition(id, await readJsonBody(init)) };
    } else if (sub === "initialize" && method === "POST") {
      const input = wordInitializeSchema.parse(await readJsonOptional(init));
      return { status: 200, data: { jobId: await queueWordInitialization(id, input.mode, 100, input), queued: true, mode: input.mode } };
    } else if (sub === "related") {
      if (method === "GET") {
        const term = params.get("term")?.trim();
        if (!term) throw new ApiError("RELATED_TERM_REQUIRED", "请选择关联词。", 400);
        return { status: 200, data: await previewRelatedWord(id, term) };
      }
      if (method === "POST") {
        return { status: 200, data: await addRelatedWord(id, await readJsonBody(init)) };
      }
    } else if (sub === "mnemonic") {
      if (method === "GET") {
        const word = await getWordDetail(id);
        if (!word) throw new ApiError("WORD_NOT_FOUND", "词条不存在。", 404);
        return {
          status: 200,
          data: {
            id: word.id,
            term: word.term,
            entryType: word.entryType,
            sourceLanguage: word.sourceLanguage,
            targetLanguage: word.targetLanguage,
            definitions: word.content.definitions,
            pronunciations: word.content.pronunciations,
            roots: word.content.roots,
            affixes: word.content.affixes,
            confusedWords: word.content.confusedWords,
            wordFamily: word.content.wordFamily,
            learning: word.content.learning,
            examples: word.content.examples,
            forms: word.content.forms,
            phrases: word.content.phrases,
            synonyms: word.content.synonyms,
            antonyms: word.content.antonyms,
          },
        };
      }
      if (method === "POST") {
        let sync = true;
        const body = (await readJsonOptional(init)) as { sync?: unknown };
        if (body && typeof body.sync === "boolean") sync = body.sync;
        if (!sync) {
          return { status: 200, data: { jobId: await queueAiTask(id, "MNEMONIC"), queued: true } };
        }
        const mnemonic = await generateChineseMnemonic(id);
        const word = await getWordDetail(id);
        return {
          status: 200,
          data: {
            success: true,
            mnemonic,
            learning: word?.content.learning ?? { pronunciationTip: null, mnemonic, commonMistakes: [] },
            roots: word?.content.roots ?? [],
            affixes: word?.content.affixes ?? [],
            confusedWords: word?.content.confusedWords ?? [],
          },
        };
      }
    } else if (sub === "examples" && method === "DELETE") {
      return { status: 200, data: await deleteExample(id, await readJsonBody(init)) };
    } else if (sub === "example-translations" && method === "POST") {
      const body = await readJsonOptional(init);
      if (body && typeof body === "object" && "index" in body) {
        const { index } = wordExampleTranslationIndexSchema.parse(body);
        return { status: 200, data: await translateExample(id, index) };
      }
      return { status: 200, data: { jobId: await queueAiTask(id, "EXAMPLE_TRANSLATIONS"), queued: true } };
    } else if (sub === "summary-translation" && method === "POST") {
      return { status: 200, data: { jobId: await queueAiTask(id, "EXAMPLE_TRANSLATIONS"), queued: true } };
    } else if (sub === "youdao-preview" && method === "POST") {
      const input = wordYoudaoPreviewSchema.parse(await readJsonOptional(init));
      return { status: 200, data: await previewYoudaoContent(id, input.term) };
    } else if (sub === "youdao-apply" && method === "POST") {
      const input = wordYoudaoApplySchema.parse(await readJsonBody(init));
      const content = normalizeDictionaryContent(input.content);
      const detail = await applyYoudaoContent(id, content, input.mode, input.attempts as ProviderAttempt[], input.newTerm);
      if (!detail) throw new ApiError("WORD_NOT_FOUND", "词条不存在。", 404);
      return { status: 200, data: detail };
    }
  }

  // ---- Manual & CSV & Article Imports ----
  if (path === "/api/manual/preview" && method === "POST") {
    return { status: 200, data: await createManualPreview(await readJsonBody(init)) };
  }
  if (path === "/api/manual/confirm" && method === "POST") {
    return { status: 200, data: await confirmManualPreview(await readJsonBody(init)) };
  }
  if (path === "/api/imports" && method === "GET") {
    return { status: 200, data: await listImportBatches(parsePositiveInt(params.get("limit"), 50, 100)) };
  }
  if (path === "/api/imports/preview" && method === "POST") {
    const form = readFormData(init);
    return { status: 200, data: await createImportPreviewFromFile(form.get("file")) };
  }
  if (path === "/api/imports/commit" && method === "POST") {
    const input = importCommitSchema.parse(await readJsonBody(init));
    const result = await commitImport(input.previewToken, input.mode, input.resetLearningProgress);
    try {
      await runBackgroundTick({ maxJobs: 1 });
    } catch (tickError) {
      console.error("[LocalBackgroundTick] on-demand tick after import failed", tickError);
    }
    return { status: 200, data: result };
  }
  const importRollbackMatch = /^\/api\/imports\/([^/]+)\/rollback$/.exec(path);
  if (importRollbackMatch && method === "POST") {
    const id = requireRouteId(importRollbackMatch[1], "IMPORT_BATCH_ID_INVALID", "导入批次 ID 无效。");
    return { status: 200, data: await rollbackImportBatch(id) };
  }
  if (path === "/api/article-import/preview" && method === "POST") {
    const input = articlePreviewSchema.parse(await readJsonBody(init));
    return {
      status: 200,
      data: await createArticlePreview({
        articleText: input.articleText,
        sourceLanguage: input.sourceLanguage,
        targetLanguage: input.targetLanguage,
        examTargets: input.examTargets,
      }),
    };
  }
  if (path === "/api/article-import/merge" && method === "POST") {
    const input = articleMergeSchema.parse(await readJsonBody(init));
    return { status: 200, data: await mergeArticlePreviews(input.tokens) };
  }
  if (path === "/api/article-import/commit" && method === "POST") {
    return { status: 200, data: await commitArticleImport(await readJsonBody(init)) };
  }

  // ---- Initialization & Background Keepalive ----
  if (path === "/api/initialization" && method === "GET") {
    const rawStatus = params.get("status");
    const status = rawStatus && INITIALIZATION_STATUSES.includes(rawStatus as InitializationStatus)
      ? (rawStatus as InitializationStatus)
      : undefined;
    const page = parsePositiveInt(params.get("page"), 1, 1000);
    const pageSize = Math.min(parsePositiveInt(params.get("pageSize"), 50, 50), 200);
    const search = params.get("search") || undefined;
    return { status: 200, data: await listInitializationJobs({ page, pageSize, status, search }) };
  }
  if (path === "/api/initialization/options" && method === "GET") {
    return { status: 200, data: await getInitializationOptions() };
  }
  if (path === "/api/initialization/status" && method === "GET") {
    return {
      status: 200,
      data: {
        summary: await getInitializationSummary(),
        wordSummary: await getWordsSummary(),
        workers: await getWorkerHeartbeats(),
      },
    };
  }
  if (path === "/api/initialization/preview" && method === "POST") {
    return { status: 200, data: await previewConfiguredInitialization(initializationPreviewSchema.parse(await readJsonBody(init))) };
  }
  if (path === "/api/initialization/bulk" && method === "POST") {
    const input = initializationBulkSchema.parse(await readJsonOptional(init));
    const configured = Boolean(input.requestedFields?.length || input.requestedProviders?.length || input.providerStrategy || input.onlyMissing !== undefined);
    if (configured) return { status: 200, data: await queueConfiguredInitialization(input) };
    return {
      status: 200,
      data: input.wordIds
        ? await queueSelectedInitialization(input.wordIds, input.mode)
        : await queueBulkInitialization(input.mode, input.onlyWithoutAi),
    };
  }
  if (path === "/api/initialization/retry" && method === "POST") {
    const input = initializationRetrySchema.parse(await readJsonBody(init));
    return { status: 200, data: { retried: "jobIds" in input ? await retryFailedJobs(input.jobIds) : await retryFailedJobsForWords(input.wordIds) } };
  }
  if (path === "/api/initialization/run" && method === "POST") {
    return { status: 200, data: await runBackgroundTick({ maxJobs: 1, timeBudgetMs: 25_000 }) };
  }
  const initJobMatch = /^\/api\/initialization\/([^/]+)$/.exec(path);
  if (initJobMatch && method === "GET") {
    const jobId = requireRouteId(initJobMatch[1], "JOB_ID_INVALID", "任务 ID 无效。");
    const details = await getJobDetails(jobId);
    if (!details) throw new ApiError("JOB_NOT_FOUND", "任务不存在。", 404);
    return { status: 200, data: details };
  }
  if (path === "/api/background/keepalive" && method === "GET") {
    if (keepaliveInFlight) {
      const summary = await getInitializationSummary();
      const queued = summary.QUEUED + summary.PENDING + summary.RUNNING;
      return { status: 200, data: { running: queued > 0, queued, claimed: 0, elapsedMs: 0 } };
    }
    keepaliveInFlight = true;
    try {
      const result = await runBackgroundTick({ maxJobs: 1 });
      const summary = await getInitializationSummary();
      const queued = summary.QUEUED + summary.PENDING + summary.RUNNING;
      return { status: 200, data: { running: queued > 0, queued, claimed: result.claimed, elapsedMs: result.elapsedMs } };
    } finally {
      keepaliveInFlight = false;
    }
  }

  // ---- Study & Reviews ----
  if (path === "/api/study/plan" && method === "GET") {
    return { status: 200, data: await getDailyStudyPlan() };
  }
  if (path === "/api/study/sessions" && method === "POST") {
    const { mode, resume, continuous } = studySessionStartSchema.parse(await readJsonOptional(init));
    return { status: 200, data: await startStudySession(mode, resume, continuous) };
  }
  const studySessionMatch = /^\/api\/study\/sessions\/([^/]+)$/.exec(path);
  if (studySessionMatch && method === "GET") {
    const id = requireRouteId(studySessionMatch[1], "SESSION_ID_INVALID", "会话 ID 无效。");
    return { status: 200, data: await getStudySession(id) };
  }
  if (path === "/api/study/answer" && method === "POST") {
    return { status: 200, data: await processReviewAnswer(studyAnswerSchema.parse(await readJsonBody(init))) };
  }
  if (path === "/api/study/skip" && method === "POST") {
    const input = studySkipSchema.parse(await readJsonBody(init));
    return { status: 200, data: await skipStudyItem(input.studySessionId, input.studySessionItemId, input.reason) };
  }
  if (path === "/api/reviews/preview" && method === "POST") {
    const { wordId } = reviewPreviewSchema.parse(await readJsonBody(init));
    return { status: 200, data: await getReviewPreview(wordId) };
  }

  // ---- Games / Match / Phonetics ----
  if (path === "/api/games/sessions" && method === "POST") {
    const { mode } = gameSessionStartSchema.parse(await readJsonBody(init));
    return { status: 200, data: await startGameSession(mode) };
  }
  const gameCompleteMatch = /^\/api\/games\/sessions\/([^/]+)\/complete$/.exec(path);
  if (gameCompleteMatch && method === "POST") {
    const sessionId = requireRouteId(gameCompleteMatch[1], "VALIDATION_ERROR", "小游戏会话 ID 无效。");
    const input = gameSessionCompleteSchema.parse(await readJsonBody(init));
    return { status: 200, data: await completeGameSession({ sessionId, ...input }) };
  }
  if (path === "/api/match/sessions" && method === "POST") {
    const input = matchSessionStartSchema.parse(await readJsonOptional(init));
    return { status: 200, data: await startMatchingSession(input) };
  }
  const matchCompleteMatch = /^\/api\/match\/sessions\/([^/]+)\/complete$/.exec(path);
  if (matchCompleteMatch && method === "POST") {
    const sessionId = requireRouteId(matchCompleteMatch[1], "VALIDATION_ERROR", "配对会话 ID 无效。");
    const input = matchSessionCompleteSchema.parse(await readJsonBody(init));
    return { status: 200, data: await completeMatchingSession({ sessionId, ...input }) };
  }
  if (path === "/api/phonetics/sessions" && method === "POST") {
    const { accent } = phoneticsSessionStartSchema.parse(await readJsonBody(init));
    return { status: 200, data: await startPhoneticGame(accent) };
  }
  const phoneticsCompleteMatch = /^\/api\/phonetics\/sessions\/([^/]+)\/complete$/.exec(path);
  if (phoneticsCompleteMatch && method === "POST") {
    const sessionId = requireRouteId(phoneticsCompleteMatch[1], "VALIDATION_ERROR", "音标训练会话 ID 无效。");
    const input = phoneticsSessionCompleteSchema.parse(await readJsonBody(init));
    return { status: 200, data: await completePhoneticGame({ sessionId, ...input }) };
  }

  // ---- Backups ----
  if (path === "/api/backups/json" && method === "GET") {
    return { status: 200, data: await createJsonBackup(), meta: { fallbackMessage: "导出 JSON 备份失败。" } };
  }
  if (path === "/api/backups/restore" && method === "POST") {
    let raw: string | null = null;
    let emptyFile = false;
    if (init?.body instanceof FormData) {
      const extracted = await extractBackupRawFromFormData(init.body);
      raw = extracted.raw;
      emptyFile = Boolean(extracted.emptyFile);
    } else {
      const body = await readJsonOptional(init);
      raw = await extractBackupRawFromJson(body);
    }
    const result = await restoreBackupWithSummary(raw, emptyFile);
    if (result.status !== 200) {
      throw new ApiError("VALIDATION_ERROR", result.body.message, result.status);
    }
    return { status: 200, data: result.body, meta: { fallbackMessage: "恢复失败。", validationMessage: "备份文件无效。" } };
  }

  // ---- Local Sync Identity Fallback ----
  if (path === "/api/sync/status" && method === "GET") {
    const state = await ensureServerSyncState();
    const { sqlite } = await import("@/db/client");
    const countRow = await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count?: number } | undefined;
    return {
      status: 200,
      data: {
        protocolVersion: CLOUD_SYNC_PROTOCOL_VERSION,
        passwordProtected: false,
        deviceId: state.deviceId,
        datasetEpoch: state.datasetEpoch,
        wordCount: countRow?.count ?? 0,
        peers: Object.values(state.peerWatermarks).sort((a, b) => b.lastSyncedAt - a.lastSyncedAt),
      },
    };
  }

  throw new ApiError("NOT_FOUND", `本地模式不支持该接口：${method} ${path}`, 404);
}

/** Executes a local API route returning the standard `{ success, data | error }` envelope + HTTP status. */
export async function dispatchLocalApiRaw(url: URL, init?: RequestInit): Promise<LocalEnvelopeResult> {
  return enqueueLocalTurn(async () => {
    await ensureBrowserDbReady();
    try {
      const result = await routeLocalRequest(url, init);
      return { status: result.status, body: { success: true, data: result.data } };
    } catch (error) {
      return wrapError(error, { fallbackMessage: "本地数据库处理请求时发生错误。" });
    }
  });
}

/** Executes a local API route and returns `data` directly or throws Error(message), matching `apiFetch`. */
export async function dispatchLocalApi<T>(url: URL, init?: RequestInit): Promise<T> {
  const result = await dispatchLocalApiRaw(url, init);
  if (result.status >= 400 || !result.body.success) {
    const msg = !result.body.success ? result.body.error.message : `请求失败：HTTP ${result.status}`;
    throw new Error(msg);
  }
  return result.body.data as T;
}
