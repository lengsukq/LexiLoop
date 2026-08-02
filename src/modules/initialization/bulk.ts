import { sqlite } from "@/db/client";
import type { AiTaskType, InitializationMode, InitializationTaskOptions } from "@/lib/types";
import { queueSelectedInitialization } from "./queue";
import { setWordOperationalStatus } from "./shared";

export async function queueBulkInitialization(
  mode: Extract<InitializationMode, "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE"> = "FILL_MISSING_FIELDS",
  onlyWithoutAi = true,
  options: InitializationTaskOptions = {},
) {
  const total = (await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count: number }).count;
  const aiFilter = onlyWithoutAi ? `WHERE NOT EXISTS (SELECT 1 FROM provider_attempts pa WHERE pa.word_id = w.id AND pa.provider_id LIKE 'ai:%' AND pa.status = 'SUCCESS')` : "";
  const candidates = await sqlite.prepare(`SELECT w.id FROM words w ${aiFilter} ORDER BY w.id ASC`).all() as Array<{ id: number }>;
  const queued = await queueSelectedInitialization(candidates.map((candidate) => candidate.id), mode, options);
  return { totalWords: total, selectedWords: queued.selectedWords, skippedAiInitialized: onlyWithoutAi ? total - candidates.length : 0, createdJobs: queued.createdJobs, updatedJobs: queued.updatedJobs, mode };
}

export async function retryFailedJobs(jobIds: number[]): Promise<number> {
  const now = Date.now();
  const statement = sqlite.prepare(`UPDATE initialization_jobs SET status = 'QUEUED', attempt_count = 0,
    available_at = ?, locked_at = NULL, locked_by = NULL, last_error = NULL, last_error_code = NULL,
    completed_at = NULL, updated_at = ? WHERE id = ? AND status = 'FAILED'`);
  let changed = 0;
  await sqlite.transaction(async () => {
    for (const id of jobIds) {
      const job = await sqlite.prepare("SELECT word_id, task_type FROM initialization_jobs WHERE id = ?").get(id) as { word_id: number; task_type: AiTaskType } | undefined;
      const result = await statement.run(now, now, id);
      changed += result.changes;
      if (result.changes && job?.task_type === "INITIALIZE") setWordOperationalStatus(job.word_id, "QUEUED", now);
    }
  })();
  return changed;
}

export async function retryFailedJobsForWords(wordIds: number[]): Promise<number> {
  const ids = [...new Set(wordIds.filter((id) => Number.isInteger(id) && id > 0))];
  if (!ids.length) return 0;
  const placeholders = ids.map(() => "?").join(",");
  const jobs = await sqlite.prepare(`SELECT id FROM initialization_jobs
    WHERE word_id IN (${placeholders}) AND status = 'FAILED'`).all(...ids) as Array<{ id: number }>;
  return retryFailedJobs(jobs.map((job) => job.id));
}
