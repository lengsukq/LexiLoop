import { sqlite } from "@/db/client";
import { ok } from "@/lib/api";
import { WORKER_STALE_AFTER_MS } from "@/lib/config";

export const dynamic = "force-dynamic";
export async function GET() {
  let database = "ok";
  try { sqlite.prepare("SELECT 1").get(); } catch { database = "error"; }
  const queue = database === "ok" ? sqlite.prepare("SELECT count(*) AS count FROM initialization_jobs WHERE status IN ('QUEUED','RUNNING')").get() as { count: number } : { count: 0 };
  const heartbeat = database === "ok" ? sqlite.prepare("SELECT worker_id, status, last_seen_at FROM worker_heartbeats ORDER BY last_seen_at DESC LIMIT 1").get() as { worker_id: string; status: string; last_seen_at: number } | undefined : undefined;
  const stale = !heartbeat || Date.now() - heartbeat.last_seen_at > WORKER_STALE_AFTER_MS;
  const workerStatus = queue.count === 0 && stale ? "not_required" : stale ? "stale" : heartbeat?.status.toLowerCase() ?? "unknown";
  const status = database === "error" ? "error" : workerStatus === "stale" ? "degraded" : "ok";
  return ok({
    status,
    database,
    backgroundEngine: { status: workerStatus, engineId: heartbeat?.worker_id ?? null, lastSeenAt: heartbeat ? new Date(heartbeat.last_seen_at).toISOString() : null },
    worker: { status: workerStatus, workerId: heartbeat?.worker_id ?? null, lastSeenAt: heartbeat ? new Date(heartbeat.last_seen_at).toISOString() : null },
    initializationQueue: queue.count,
    version: "1.0.0",
  }, { status: database === "error" ? 503 : 200, headers: { "Cache-Control": "no-store" } });
}
