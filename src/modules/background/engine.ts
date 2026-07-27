import { claimJobs, processJob, updateHeartbeat } from "@/modules/initialization/service";
import { sqlite } from "@/db/client";

type EngineState = {
  started: boolean;
  stopping: boolean;
  workerId: string;
  concurrency: number;
  pollIntervalMs: number;
  loopPromise: Promise<void> | null;
};

const globalEngine = globalThis as typeof globalThis & { __lexiloopBackgroundEngine?: EngineState };

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    timer.unref?.();
  });
}

function state(): EngineState {
  if (!globalEngine.__lexiloopBackgroundEngine) {
    globalEngine.__lexiloopBackgroundEngine = {
      started: false,
      stopping: false,
      workerId: process.env.BACKGROUND_ENGINE_ID ?? process.env.WORKER_ID ?? `lexiloop-app-${process.pid}`,
      concurrency: Math.max(1, Math.min(10, Number(process.env.BACKGROUND_CONCURRENCY ?? process.env.WORKER_CONCURRENCY ?? 2))),
      pollIntervalMs: Math.max(250, Number(process.env.BACKGROUND_POLL_INTERVAL_MS ?? process.env.WORKER_POLL_INTERVAL_MS ?? 1_000)),
      loopPromise: null,
    };
  }
  return globalEngine.__lexiloopBackgroundEngine;
}

function getConcurrencyFromSettings(): number | null {
  try {
    const row = sqlite.prepare("SELECT value_json FROM settings WHERE key = 'backgroundConcurrency'").get() as { value_json: string } | undefined;
    if (!row) return null;
    const value = Number(JSON.parse(row.value_json));
    return Number.isInteger(value) && value >= 1 && value <= 10 ? value : null;
  } catch { return null; }
}

async function runLoop(engine: EngineState): Promise<void> {
  console.log(`[BackgroundEngine] ${engine.workerId} started, concurrency=${engine.concurrency}`);
  updateHeartbeat(engine.workerId, "STARTING", undefined, {
    pid: process.pid,
    concurrency: engine.concurrency,
    mode: "embedded",
  });
  while (!engine.stopping) {
    try {
      const jobs = claimJobs(engine.workerId, getConcurrencyFromSettings() ?? engine.concurrency);
      if (jobs.length === 0) {
        updateHeartbeat(engine.workerId, "IDLE", undefined, {
          pid: process.pid,
          concurrency: engine.concurrency,
          mode: "embedded",
        });
        await sleep(engine.pollIntervalMs);
        continue;
      }
      updateHeartbeat(engine.workerId, "WORKING", jobs[0]?.id, {
        pid: process.pid,
        concurrency: engine.concurrency,
        claimed: jobs.length,
        mode: "embedded",
      });
      await Promise.allSettled(jobs.map(async (job) => {
        updateHeartbeat(engine.workerId, "WORKING", job.id, {
          pid: process.pid,
          wordId: job.wordId,
          mode: "embedded",
        });
        await processJob(job);
      }));
    } catch (error) {
      console.error("[BackgroundEngine] loop error", error);
      updateHeartbeat(engine.workerId, "ERROR", undefined, {
        pid: process.pid,
        error: String(error),
        mode: "embedded",
      });
      await sleep(Math.max(2_000, engine.pollIntervalMs));
    }
  }
  updateHeartbeat(engine.workerId, "STOPPING", undefined, { pid: process.pid, mode: "embedded" });
  engine.started = false;
  engine.loopPromise = null;
}

export function startBackgroundEngine(): void {
  if (process.env.BACKGROUND_ENGINE_ENABLED === "false") {
    console.log("[BackgroundEngine] disabled by BACKGROUND_ENGINE_ENABLED=false");
    return;
  }
  const engine = state();
  if (engine.started) return;
  engine.started = true;
  engine.stopping = false;
  engine.loopPromise = runLoop(engine).catch((error) => {
    console.error("[BackgroundEngine] fatal error", error);
    updateHeartbeat(engine.workerId, "ERROR", undefined, { pid: process.pid, error: String(error), mode: "embedded" });
    engine.started = false;
    engine.loopPromise = null;
  });
}

export function stopBackgroundEngine(): void {
  const engine = state();
  engine.stopping = true;
}

export function getBackgroundEngineState() {
  const engine = state();
  return {
    started: engine.started,
    stopping: engine.stopping,
    workerId: engine.workerId,
    concurrency: engine.concurrency,
    pollIntervalMs: engine.pollIntervalMs,
  };
}
