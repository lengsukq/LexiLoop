import { runBackgroundTick } from "@/modules/background/tick";

const DOCKER_WORKER_ID = "lexiloop-docker";
const INTERVAL_MS = 10_000;
const MAX_JOBS_PER_TICK = 5;

let timer: ReturnType<typeof setInterval> | null = null;
let running = false;

async function tickOnce(): Promise<void> {
  if (running) return;
  running = true;
  try {
    await runBackgroundTick({ maxJobs: MAX_JOBS_PER_TICK, workerId: DOCKER_WORKER_ID });
  } catch (error) {
    console.error("[DockerTick] tick error", error);
  } finally {
    running = false;
  }
}

export function startDockerTick(): void {
  if (timer) return;
  console.log(`[DockerTick] starting interval every ${INTERVAL_MS}ms (workerId=${DOCKER_WORKER_ID})`);
  void tickOnce();
  timer = setInterval(() => {
    void tickOnce();
  }, INTERVAL_MS);
}

export function stopDockerTick(): void {
  if (!timer) return;
  clearInterval(timer);
  timer = null;
}
