import { claimJobs, processJob, updateHeartbeat } from "@/modules/initialization/service";
import { runMaintenance } from "@/modules/background/maintenance";
import { getTodaySuggestion, suggestionDateKey } from "@/modules/suggestions/service";
import { MINUTE_MS } from "@/lib/time";

const MAINTENANCE_INTERVAL_MS = 10 * MINUTE_MS; // 10 minutes
const SUGGESTION_CHECK_INTERVAL_MS = MINUTE_MS; // 1 minute
const SUGGESTION_GENERATION_HOUR = 0;
const SUGGESTION_GENERATION_MINUTE = 5;
const APP_TIMEZONE = process.env.APP_TIMEZONE ?? "Asia/Shanghai";
const DEFAULT_MAX_JOBS = 3;

/**
 * 固定 workerId 用于 serverless 触发路径。worker_heartbeats 按 worker_id upsert，
 * 固定 ID 避免每次冷启动生成不同 ID 导致心跳表无限膨胀。
 */
export const SERVERLESS_WORKER_ID = "lexiloop-serverless";

type TickState = {
  lastMaintenanceAt: number;
  lastSuggestionCheckAt: number;
  lastSuggestionDateKey: string | null;
  suggestionPromise: Promise<void> | null;
};

const globalTick = globalThis as typeof globalThis & { __lexiloopBackgroundTick?: TickState };

function state(): TickState {
  if (!globalTick.__lexiloopBackgroundTick) {
    globalTick.__lexiloopBackgroundTick = {
      lastMaintenanceAt: 0,
      lastSuggestionCheckAt: 0,
      lastSuggestionDateKey: null,
      suggestionPromise: null,
    };
  }
  return globalTick.__lexiloopBackgroundTick;
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

async function maybeRunMaintenance(): Promise<void> {
  const now = Date.now();
  if (now - state().lastMaintenanceAt < MAINTENANCE_INTERVAL_MS) return;
  state().lastMaintenanceAt = now;
  try {
    const result = await runMaintenance();
    const touched = result.expiredPreviews + result.decayedWrongWords + result.retriedJobs + result.expiredSessions + result.expiredBatches + result.purgedPreviews;
    if (touched > 0) console.log(`[BackgroundTick] maintenance:`, result);
  } catch (error) {
    console.error("[BackgroundTick] maintenance error", error);
  }
}

function maybeGenerateDailySuggestion(): void {
  const now = Date.now();
  if (now - state().lastSuggestionCheckAt < SUGGESTION_CHECK_INTERVAL_MS) return;
  state().lastSuggestionCheckAt = now;
  let clock: { hour: number; minute: number };
  let dateKey: string;
  try {
    clock = localClock(now);
    dateKey = suggestionDateKey(now);
  } catch (error) {
    console.error(`[BackgroundTick] invalid APP_TIMEZONE=${APP_TIMEZONE}`, error);
    return;
  }
  const afterScheduledTime = clock.hour > SUGGESTION_GENERATION_HOUR
    || (clock.hour === SUGGESTION_GENERATION_HOUR && clock.minute >= SUGGESTION_GENERATION_MINUTE);
  if (!afterScheduledTime) return;
  if (state().lastSuggestionDateKey === dateKey || state().suggestionPromise) return;
  // getTodaySuggestion 内部先查 DB 缓存且保存时依赖 date_key 唯一约束，跨实例重复触发也安全。
  state().suggestionPromise = getTodaySuggestion({ now })
    .then((suggestion) => {
      state().lastSuggestionDateKey = dateKey;
      console.log(`[BackgroundTick] daily suggestion ready: ${suggestion.dateKey}, generator=${suggestion.generator}`);
    })
    .catch((error) => {
      console.error("[BackgroundTick] daily suggestion error", error);
    })
    .finally(() => {
      state().suggestionPromise = null;
    });
}

export interface BackgroundTickResult {
  workerId: string;
  claimed: number;
  processed: number;
  elapsedMs: number;
}

/**
 * 执行一轮后台任务处理：在时间预算内循环领取并处理初始化任务、运行一次幂等维护、
 * 按需生成每日建议，最后更新心跳。可在任意环境重复调用，无需常驻循环。
 */
export async function runBackgroundTick(
  options: { maxJobs?: number; timeBudgetMs?: number; workerId?: string } = {},
): Promise<BackgroundTickResult> {
  const workerId = options.workerId ?? SERVERLESS_WORKER_ID;
  const maxJobs = Math.max(1, options.maxJobs ?? DEFAULT_MAX_JOBS);
  const timeBudgetMs = Math.max(0, options.timeBudgetMs ?? 0);
  const startedAt = Date.now();
  let totalClaimed = 0;

  await maybeRunMaintenance();
  maybeGenerateDailySuggestion();

  for (;;) {
    const jobs = await claimJobs(workerId, maxJobs);
    if (jobs.length === 0) break;
    await Promise.allSettled(jobs.map(async (job) => {
      updateHeartbeat(workerId, "WORKING", job.id, {
        pid: process.pid,
        wordId: job.wordId,
        mode: "tick",
      });
      await processJob(job);
    }));
    totalClaimed += jobs.length;
    if (timeBudgetMs <= 0) break;
    if (Date.now() - startedAt >= timeBudgetMs) break;
  }

  updateHeartbeat(workerId, "IDLE", undefined, {
    pid: process.pid,
    claimed: totalClaimed,
    mode: "tick",
  });

  return {
    workerId,
    claimed: totalClaimed,
    processed: totalClaimed,
    elapsedMs: Date.now() - startedAt,
  };
}
