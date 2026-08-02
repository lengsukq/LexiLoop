import { sqlite } from "@/db/client";

export const MAX_ACTIVE_ANSWER_DURATION_MS = 10 * 60 * 1000;

export function boundedActiveDurationMs(value: number | null | undefined): number | null {
  if (value === null || value === undefined || !Number.isFinite(value)) return null;
  return Math.max(0, Math.min(MAX_ACTIVE_ANSWER_DURATION_MS, Math.round(value)));
}

export async function sessionActiveDurationMs(sessionId: number): Promise<number> {
  const row = await sqlite.prepare(`SELECT COALESCE(SUM(
      CASE
        WHEN duration_ms IS NULL OR duration_ms <= 0 THEN 0
        WHEN duration_ms > ? THEN ?
        ELSE duration_ms
      END
    ), 0) AS duration
    FROM review_logs WHERE study_session_id = ?`)
    .get(MAX_ACTIVE_ANSWER_DURATION_MS, MAX_ACTIVE_ANSWER_DURATION_MS, sessionId) as { duration: number };
  return Math.max(0, Number(row.duration ?? 0));
}

export async function closeStudySessionWithActiveDuration(sessionId: number, completedAt: number): Promise<void> {
  await sqlite.prepare("UPDATE study_sessions SET completed_at = ?, duration_ms = ? WHERE id = ?")
    .run(completedAt, await sessionActiveDurationMs(sessionId), sessionId);
}
