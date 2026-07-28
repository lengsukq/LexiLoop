import { sqlite } from "@/db/client";

/**
 * Periodic maintenance tasks executed by the Background Engine.
 * Each task is idempotent and safe to run concurrently with normal operations.
 */

const WRONG_WORD_DECAY_DAYS = 30;
const IMPORT_BATCH_EXPIRY_MS = 24 * 60 * 60 * 1000;
const FAILED_RETRY_COOLDOWN_MS = 60 * 60 * 1000; // 1 hour between auto-retries

/** Mark expired manual_previews as EXPIRED and delete expired import_previews. */
export function cleanupExpiredPreviews(): number {
  const now = Date.now();
  return sqlite.transaction(() => {
    const manual = sqlite.prepare(
      "UPDATE manual_previews SET status = 'EXPIRED' WHERE status = 'PREVIEW' AND expires_at < ?",
    ).run(now);
    const imports = sqlite.prepare("DELETE FROM import_previews WHERE expires_at < ?").run(now);
    return manual.changes + imports.changes;
  }).immediate();
}

/** Deactivate wrong words that haven't been answered wrong in N days (decay). */
export function decayStaleWrongWords(): number {
  const now = Date.now();
  const cutoff = now - WRONG_WORD_DECAY_DAYS * 24 * 60 * 60 * 1000;
  const result = sqlite.prepare(`UPDATE wrong_word_states
    SET active = 0, resolved_at = ?, updated_at = ?
    WHERE active = 1 AND last_wrong_at IS NOT NULL AND last_wrong_at < ?
      AND (last_correct_at IS NULL OR last_correct_at < ?)`).run(now, now, cutoff, cutoff);
  return result.changes;
}

/** Re-queue FAILED initialization jobs that still have remaining attempts. */
export function autoRetryFailedJobs(): number {
  const now = Date.now();
  const result = sqlite.prepare(`UPDATE initialization_jobs
    SET status = 'QUEUED', locked_at = NULL, locked_by = NULL,
        available_at = ?, last_error_code = 'AUTO_RETRY', updated_at = ?
    WHERE status = 'FAILED' AND attempt_count < max_attempts
      AND (completed_at IS NULL OR completed_at < ?)`).run(now, now, now - FAILED_RETRY_COOLDOWN_MS);
  if (result.changes > 0) {
    const queuedWords = sqlite.prepare(
      "SELECT DISTINCT word_id FROM initialization_jobs WHERE status = 'QUEUED' AND task_type = 'INITIALIZE'",
    ).all() as Array<{ word_id: number }>;
    for (const job of queuedWords) {
      sqlite.prepare("UPDATE words SET initialization_status = 'QUEUED', updated_at = ? WHERE id = ? AND initialization_status = 'FAILED'")
        .run(now, job.word_id);
    }
  }
  return result.changes;
}

/** Expire study sessions that have been pending for too long (24h). */
export function expireStaleSessions(): number {
  const now = Date.now();
  const staleBefore = now - 24 * 60 * 60 * 1000;
  return sqlite.transaction(() => {
    const stale = sqlite.prepare(`SELECT id, started_at FROM study_sessions
      WHERE completed_at IS NULL AND started_at < ?`).all(staleBefore) as Array<{ id: number; started_at: number }>;
    let expiredItems = 0;
    for (const session of stale) {
      const result = sqlite.prepare(`UPDATE study_session_items
        SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED'
        WHERE study_session_id = ? AND status = 'PENDING'`).run(now, session.id);
      expiredItems += result.changes;
      sqlite.prepare(`UPDATE study_sessions SET completed_at = ?, duration_ms = ?,
        completed_count = completed_count + ?, skipped_count = skipped_count + ?
        WHERE id = ?`).run(now, now - session.started_at, result.changes, result.changes, session.id);
    }
    return expiredItems;
  }).immediate();
}

/** Mark import batches stuck in PENDING for over 24h as FAILED. */
export function expireStaleBatches(): number {
  const now = Date.now();
  const result = sqlite.prepare(`UPDATE import_batches
    SET status = 'FAILED', completed_at = ?
    WHERE status = 'PENDING' AND created_at < ?`).run(now, now - IMPORT_BATCH_EXPIRY_MS);
  return result.changes;
}

/** Delete old expired manual_previews rows (already EXPIRED for over 7 days) to reclaim space. */
export function purgeOldExpiredPreviews(): number {
  const cutoff = Date.now() - 7 * 24 * 60 * 60 * 1000;
  return sqlite.prepare("DELETE FROM manual_previews WHERE status = 'EXPIRED' AND expires_at < ?").run(cutoff).changes;
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
export function runMaintenance(): MaintenanceResult {
  return {
    expiredPreviews: cleanupExpiredPreviews(),
    decayedWrongWords: decayStaleWrongWords(),
    retriedJobs: autoRetryFailedJobs(),
    expiredSessions: expireStaleSessions(),
    expiredBatches: expireStaleBatches(),
    purgedPreviews: purgeOldExpiredPreviews(),
  };
}
