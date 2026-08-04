import { sqlite } from "@/db/client";
import { updateHeartbeat } from "@/modules/initialization/service";
import { runBackgroundTick } from "@/modules/background/tick";

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
      workerId: `lexiloop-app-${process.pid}`,
      concurrency: 2,
      pollIntervalMs: 1_000,
      loopPromise: null,
    };
  }
  return globalEngine.__lexiloopBackgroundEngine;
}

async function getConcurrencyFromSettings(): Promise<number | null> {
  try {
    const row = await sqlite.prepare("SELECT value_json FROM settings WHERE key = 'backgroundConcurrency'").get() as { value_json: string } | undefined;
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
      await runBackgroundTick({
        workerId: engine.workerId,
        maxJobs: (await getConcurrencyFromSettings()) ?? engine.concurrency,
      });
      await sleep(engine.pollIntervalMs);
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
  if (process.env.VERCEL === "1") {
    console.log("[BackgroundEngine] skipped on Vercel; initialization is driven by /api/background/tick and on-demand triggers");
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
