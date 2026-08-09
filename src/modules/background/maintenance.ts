import { sqlite } from "@/db/client";
import { closeStudySessionWithActiveDuration } from "@/modules/reviews/duration";
import { DAY_MS, HOUR_MS, WEEK_MS } from "@/lib/time";

/**
 * Periodic maintenance tasks executed by the Background Engine.
 * Each task is idempotent and safe to run concurrently with normal operations.
 */

const WRONG_WORD_DECAY_DAYS = 30;
const IMPORT_BATCH_EXPIRY_MS = DAY_MS;
const FAILED_RETRY_COOLDOWN_MS = HOUR_MS; // 1 hour between auto-retries

/** Mark expired manual_previews as EXPIRED and delete expired import_previews. */
export async function cleanupExpiredPreviews(): Promise<number> {
  const now = Date.now();
  return await sqlite.transaction(async () => {
    const manual = await sqlite.prepare(
      "UPDATE manual_previews SET status = 'EXPIRED' WHERE status = 'PREVIEW' AND expires_at < ?",
    ).run(now);
    const imports = await sqlite.prepare("DELETE FROM import_previews WHERE expires_at < ?").run(now);
    return manual.changes + imports.changes;
  }).immediate();
}

/** Deactivate wrong words that haven't been answered wrong in N days (decay). */
export async function decayStaleWrongWords(): Promise<number> {
  const now = Date.now();
  const cutoff = now - WRONG_WORD_DECAY_DAYS * DAY_MS;
  const result = await sqlite.prepare(`UPDATE wrong_word_states
    SET active = 0, resolved_at = ?, updated_at = ?
    WHERE active = 1 AND last_wrong_at IS NOT NULL AND last_wrong_at < ?
      AND (last_correct_at IS NULL OR last_correct_at < ?)`).run(now, now, cutoff, cutoff);
  return result.changes;
}

/** Re-queue FAILED initialization jobs that still have remaining attempts. */
export async function autoRetryFailedJobs(): Promise<number> {
  const now = Date.now();
  return sqlite.transaction(async () => {
    // Step 1: Delete FAILED jobs that already have a QUEUED/RUNNING counterpart.
    // These are redundant and would cause UNIQUE constraint violations if retried.
    await sqlite.prepare(`DELETE FROM initialization_jobs
      WHERE status = 'FAILED'
        AND EXISTS (
          SELECT 1 FROM initialization_jobs AS other
          WHERE other.word_id = initialization_jobs.word_id
            AND other.task_type = initialization_jobs.task_type
            AND other.id != initialization_jobs.id
            AND other.status IN ('QUEUED', 'RUNNING')
        )`).run();

    // Step 2: Deduplicate remaining FAILED jobs — keep only the first one per (word_id, task_type).
    // Multiple FAILED jobs for the same word could be queued if a user re-triggers initialization
    // before the maintenance loop runs, and updating them all to QUEUED would hit the partial unique index.
    await sqlite.prepare(`DELETE FROM initialization_jobs
      WHERE status = 'FAILED'
        AND id > (
          SELECT MIN(id) FROM initialization_jobs AS keep
          WHERE keep.word_id = initialization_jobs.word_id
            AND keep.task_type = initialization_jobs.task_type
            AND keep.status = initialization_jobs.status
        )`).run();

    // Step 3: Retry remaining FAILED jobs that haven't exhausted their attempts.
    const result = await sqlite.prepare(`UPDATE initialization_jobs
      SET status = 'QUEUED', locked_at = NULL, locked_by = NULL,
          available_at = ?, last_error_code = 'AUTO_RETRY', updated_at = ?
      WHERE status = 'FAILED' AND attempt_count < max_attempts
        AND (completed_at IS NULL OR completed_at < ?)`).run(now, now, now - FAILED_RETRY_COOLDOWN_MS);

    if (result.changes > 0) {
      const queuedWords = await sqlite.prepare(
        "SELECT DISTINCT word_id FROM initialization_jobs WHERE status = 'QUEUED' AND task_type = 'INITIALIZE'",
      ).all() as Array<{ word_id: number }>;
      for (const job of queuedWords) {
        await sqlite.prepare("UPDATE words SET initialization_status = 'QUEUED', updated_at = ? WHERE id = ? AND initialization_status = 'FAILED'")
          .run(now, job.word_id);
      }
    }
    return result.changes;
  }).immediate();
}

/** Expire study sessions that have been pending for too long (24h). */
export async function expireStaleSessions(): Promise<number> {
  const now = Date.now();
  const staleBefore = now - DAY_MS;
  return await sqlite.transaction(async () => {
    const stale = await sqlite.prepare(`SELECT id FROM study_sessions
      WHERE completed_at IS NULL AND started_at < ?`).all(staleBefore) as Array<{ id: number }>;
    let expiredItems = 0;
    for (const session of stale) {
      const result = await sqlite.prepare(`UPDATE study_session_items
        SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED'
        WHERE study_session_id = ? AND status = 'PENDING'`).run(now, session.id);
      expiredItems += result.changes;
      await sqlite.prepare(`UPDATE study_sessions SET completed_count = completed_count + ?,
        skipped_count = skipped_count + ? WHERE id = ?`)
        .run(result.changes, result.changes, session.id);
      await closeStudySessionWithActiveDuration(session.id, now);
    }
    return expiredItems;
  }).immediate();
}

/** Mark import batches stuck in PENDING for over 24h as FAILED. */
export async function expireStaleBatches(): Promise<number> {
  const now = Date.now();
  const result = await sqlite.prepare(`UPDATE import_batches
    SET status = 'FAILED', completed_at = ?
    WHERE status = 'PENDING' AND created_at < ?`).run(now, now - IMPORT_BATCH_EXPIRY_MS);
  return result.changes;
}

/** Delete old expired manual_previews rows (already EXPIRED for over 7 days) to reclaim space. */
export async function purgeOldExpiredPreviews(): Promise<number> {
  const cutoff = Date.now() - WEEK_MS;
  return (await sqlite.prepare("DELETE FROM manual_previews WHERE status = 'EXPIRED' AND expires_at < ?").run(cutoff)).changes;
}

export interface MaintenanceResult {
  expiredPreviews: number;
  decayedWrongWords: number;
  retriedJobs: number;
  expiredSessions: number;
  expiredBatches: number;
  purgedPreviews: number;
}

/** Run all maintenance tasks. Called periodically by the Background Engine. */
export async function runMaintenance(): Promise<MaintenanceResult> {
  return {
    expiredPreviews: await cleanupExpiredPreviews(),
    decayedWrongWords: await decayStaleWrongWords(),
    retriedJobs: await autoRetryFailedJobs(),
    expiredSessions: await expireStaleSessions(),
    expiredBatches: await expireStaleBatches(),
    purgedPreviews: await purgeOldExpiredPreviews(),
  };
}
