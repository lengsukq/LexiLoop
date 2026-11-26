import { apiFetch } from "@/lib/client-api";

interface AiTaskDetail {
  job: { status: string; lastError: string | null; lastErrorCode: string | null };
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

/** Wait for the durable background queue without keeping an AI request open in the browser. */
export async function waitForAiTask(jobId: number, timeoutMs = 90_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const task = await apiFetch<AiTaskDetail>(`/api/initialization/${jobId}`);
    if (["READY", "PARTIAL"].includes(task.job.status)) return;
    if (["FAILED", "DISABLED"].includes(task.job.status)) throw new Error(task.job.lastError ?? "AI 任务失败，请在初始化页查看详情。");
    await sleep(800);
  }
  throw new Error("AI 任务仍在排队，请稍后刷新词条查看结果。");
}
