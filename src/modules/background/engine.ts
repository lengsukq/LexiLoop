import { claimJobs, processJob, updateHeartbeat } from "@/modules/initialization/service";
import { runMaintenance } from "@/modules/background/maintenance";
import { getTodaySuggestion, suggestionDateKey } from "@/modules/suggestions/service";
import { sqlite } from "@/db/client";

type EngineState = {
  started: boolean;
  stopping: boolean;
  workerId: string;
  concurrency: number;
  pollIntervalMs: number;
  loopPromise: Promise<void> | null;
  lastMaintenanceAt: number;
  lastSuggestionCheckAt: number;
  lastSuggestionDateKey: string | null;
  suggestionPromise: Promise<void> | null;
};

const MAINTENANCE_INTERVAL_MS = 10 * 60 * 1000; // 10 minutes
const SUGGESTION_CHECK_INTERVAL_MS = 60 * 1000; // 1 minute
const SUGGESTION_GENERATION_HOUR = 0;
const SUGGESTION_GENERATION_MINUTE = 5;
const APP_TIMEZONE = process.env.APP_TIMEZONE ?? "Asia/Shanghai";

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
      lastMaintenanceAt: 0,
      lastSuggestionCheckAt: 0,
      lastSuggestionDateKey: null,
      suggestionPromise: null,
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

function maybeRunMaintenance(engine: EngineState): void {
  const now = Date.now();
  if (now - engine.lastMaintenanceAt < MAINTENANCE_INTERVAL_MS) return;
  engine.lastMaintenanceAt = now;
  try {
    const result = runMaintenance();
    const touched = result.expiredPreviews + result.decayedWrongWords + result.retriedJobs + result.expiredSessions + result.expiredBatches + result.purgedPreviews;
    if (touched > 0) console.log(`[BackgroundEngine] maintenance:`, result);
  } catch (error) {
    console.error("[BackgroundEngine] maintenance error", error);
  }
}

function localClock(timestamp: number): { hour: number; minute: number } {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: APP_TIMEZONE,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(timestamp));
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return { hour: Number(value.hour ?? 0), minute: Number(value.minute ?? 0) };
}

function maybeGenerateDailySuggestion(engine: EngineState): void {
  const now = Date.now();
  if (now - engine.lastSuggestionCheckAt < SUGGESTION_CHECK_INTERVAL_MS) return;
  engine.lastSuggestionCheckAt = now;

  let clock: { hour: number; minute: number };
  let dateKey: string;
  try {
    clock = localClock(now);
    dateKey = suggestionDateKey(now);
  } catch (error) {
    console.error(`[BackgroundEngine] invalid APP_TIMEZONE=${APP_TIMEZONE}`, error);
    return;
  }
  const afterScheduledTime = clock.hour > SUGGESTION_GENERATION_HOUR
    || (clock.hour === SUGGESTION_GENERATION_HOUR && clock.minute >= SUGGESTION_GENERATION_MINUTE);
  if (!afterScheduledTime) return;

  if (engine.lastSuggestionDateKey === dateKey || engine.suggestionPromise) return;

  engine.suggestionPromise = getTodaySuggestion({ now })
    .then((suggestion) => {
      engine.lastSuggestionDateKey = dateKey;
      console.log(`[BackgroundEngine] daily suggestion ready: ${suggestion.dateKey}, generator=${suggestion.generator}`);
    })
    .catch((error) => {
      console.error("[BackgroundEngine] daily suggestion error", error);
    })
    .finally(() => {
      engine.suggestionPromise = null;
    });
}

async function runLoop(engine: EngineState): Promise<void> {
  console.log(`[BackgroundEngine] ${engine.workerId} started, concurrency=${engine.concurrency}`);
  updateHeartbeat(engine.workerId, "STARTING", undefined, {
    pid: process.pid,
    concurrency: engine.concurrency,
    mode: "embedded",
  });
  maybeRunMaintenance(engine);
  maybeGenerateDailySuggestion(engine);
  while (!engine.stopping) {
    try {
      maybeRunMaintenance(engine);
      maybeGenerateDailySuggestion(engine);
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
