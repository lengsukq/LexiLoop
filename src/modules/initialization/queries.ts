import { sqlite } from "@/db/client";
import type { InitializationStatus } from "@/lib/types";
export { getJobDetails } from "./job-details";
export { getInitializationOptions } from "./options";

export async function getInitializationSummary() {
  const counts = await sqlite.prepare("SELECT status, COUNT(*) AS count FROM initialization_jobs GROUP BY status").all() as Array<{ status: string; count: number }>;
  const result: Record<InitializationStatus, number> = { PENDING: 0, QUEUED: 0, RUNNING: 0, READY: 0, PARTIAL: 0, FAILED: 0, DISABLED: 0 };
  for (const row of counts) result[row.status as InitializationStatus] = Number(row.count);
  return result;
}

export async function getWordsSummary() {
  const counts = await sqlite.prepare("SELECT initialization_status AS status, COUNT(*) AS count FROM words GROUP BY initialization_status").all() as Array<{ status: string; count: number }>;
  const result: Record<InitializationStatus, number> = { PENDING: 0, QUEUED: 0, RUNNING: 0, READY: 0, PARTIAL: 0, FAILED: 0, DISABLED: 0 };
  for (const row of counts) result[row.status as InitializationStatus] = Number(row.count);
  return result;
}

const AGGREGATE_STATUS_SQL = `
  CASE
    WHEN SUM(CASE WHEN j.status = 'RUNNING' THEN 1 ELSE 0 END) > 0 THEN 'RUNNING'
    WHEN SUM(CASE WHEN j.status IN ('QUEUED', 'PENDING') THEN 1 ELSE 0 END) > 0 THEN 'QUEUED'
    WHEN SUM(CASE WHEN j.status = 'FAILED' THEN 1 ELSE 0 END) > 0 THEN 'FAILED'
    WHEN SUM(CASE WHEN j.status = 'PARTIAL' THEN 1 ELSE 0 END) > 0 THEN 'PARTIAL'
    ELSE 'READY'
  END
`;

export interface InitializationWordRecord {
  wordId: number;
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  status: string;
  taskCount: number;
  completedTaskCount: number;
  failedTaskCount: number;
  activeTaskCount: number;
  updatedAt: number;
  errorSummary: string | null;
  tasks: Array<{
    id: number;
    taskType: string;
    status: string;
    mode: string;
    attemptCount: number;
    maxAttempts: number;
    lastError: string | null;
    lastErrorCode: string | null;
    createdAt: number;
    updatedAt: number;
    completedAt: number | null;
  }>;
}

export async function listInitializationJobs(options: { page?: number; pageSize?: number; status?: InitializationStatus; search?: string } = {}) {
  const { page = 1, pageSize = 50, status: statusFilter, search } = options;
  const where: string[] = ["1 = 1"];
  const params: Array<string | number> = [];
  if (search) {
    where.push("(w.term ILIKE ? ESCAPE '\\' OR w.normalized_term ILIKE ? ESCAPE '\\')");
    const escaped = search.replace(/[\\%_]/g, "\\$&");
    params.push(`%${escaped}%`, `%${escaped}%`);
  }
  const having = statusFilter ? `HAVING ${AGGREGATE_STATUS_SQL} = ?` : "";
  const havingParams = statusFilter ? [statusFilter] : [];
  const from = `FROM initialization_jobs j INNER JOIN words w ON w.id = j.word_id WHERE ${where.join(" AND ")} GROUP BY w.id`;

  const totalRow = await sqlite.prepare(`
    SELECT COUNT(*) AS total FROM (
      SELECT w.id ${from} ${having}
    ) grouped
  `).get(...params, ...havingParams) as { total: number };
  const total = Number(totalRow.total ?? 0);

  const rows = await sqlite.prepare(`
    SELECT
      w.id AS word_id,
      w.term,
      w.normalized_term,
      w.source_language,
      w.target_language,
      ${AGGREGATE_STATUS_SQL} AS aggregate_status,
      COUNT(j.id) AS task_count,
      SUM(CASE WHEN j.status IN ('READY', 'PARTIAL', 'DISABLED') THEN 1 ELSE 0 END) AS completed_task_count,
      SUM(CASE WHEN j.status = 'FAILED' THEN 1 ELSE 0 END) AS failed_task_count,
      SUM(CASE WHEN j.status IN ('QUEUED', 'PENDING', 'RUNNING') THEN 1 ELSE 0 END) AS active_task_count,
      MAX(j.updated_at) AS updated_at
    ${from}
    ${having}
    ORDER BY MAX(j.updated_at) DESC, w.id DESC
    LIMIT ? OFFSET ?
  `).all(...params, ...havingParams, pageSize, (page - 1) * pageSize) as Array<Record<string, unknown>>;

  const wordIds = rows.map((row) => Number(row.word_id));
  const taskRows = wordIds.length
    ? await sqlite.prepare(`SELECT id, word_id, task_type, status, mode, attempt_count, max_attempts,
        last_error, last_error_code, created_at, updated_at, completed_at
        FROM initialization_jobs
        WHERE word_id IN (${wordIds.map(() => "?").join(",")})
        ORDER BY word_id ASC, updated_at DESC, id DESC`).all(...wordIds) as Array<Record<string, unknown>>
    : [];
  const tasksByWord = new Map<number, InitializationWordRecord["tasks"]>();
  for (const task of taskRows) {
    const wordId = Number(task.word_id);
    const tasks = tasksByWord.get(wordId) ?? [];
    tasks.push({
      id: Number(task.id),
      taskType: String(task.task_type),
      status: String(task.status),
      mode: String(task.mode),
      attemptCount: Number(task.attempt_count ?? 0),
      maxAttempts: Number(task.max_attempts ?? 0),
      lastError: task.last_error === null || task.last_error === undefined ? null : String(task.last_error),
      lastErrorCode: task.last_error_code === null || task.last_error_code === undefined ? null : String(task.last_error_code),
      createdAt: Number(task.created_at),
      updatedAt: Number(task.updated_at),
      completedAt: task.completed_at === null || task.completed_at === undefined ? null : Number(task.completed_at),
    });
    tasksByWord.set(wordId, tasks);
  }

  const items: InitializationWordRecord[] = rows.map((row) => {
    const wordId = Number(row.word_id);
    const tasks = tasksByWord.get(wordId) ?? [];
    const errorSummary = tasks.find((task) => task.status === "FAILED" && task.lastError)?.lastError ?? null;
    return {
      wordId,
      term: String(row.term),
      normalizedTerm: String(row.normalized_term),
      sourceLanguage: String(row.source_language),
      targetLanguage: String(row.target_language),
      status: String(row.aggregate_status),
      taskCount: Number(row.task_count ?? 0),
      completedTaskCount: Number(row.completed_task_count ?? 0),
      failedTaskCount: Number(row.failed_task_count ?? 0),
      activeTaskCount: Number(row.active_task_count ?? 0),
      updatedAt: Number(row.updated_at),
      errorSummary,
      tasks,
    };
  });
  return { items, total };
}

export async function getWorkerHeartbeats() {
  return await sqlite.prepare("SELECT * FROM worker_heartbeats ORDER BY last_seen_at DESC").all();
}
