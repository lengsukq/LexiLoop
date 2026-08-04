import { ok, internalError } from "@/lib/api";
import { getInitializationSummary, getWordsSummary, getWorkerHeartbeats } from "@/modules/initialization/service";
import { runBackgroundTick } from "@/modules/background/tick";
export const dynamic = "force-dynamic";
export async function GET() {
  try {
    // 该接口被初始化页面每 3 秒轮询；在返回前顺带处理一批任务，
    // 使 serverless 环境（Vercel）下无需常驻 Worker 也能持续推进初始化队列。
    try { await runBackgroundTick({ maxJobs: 3 }); } catch (tickError) { console.error("[BackgroundTick] on-demand tick failed", tickError); }
    return ok({ summary: await getInitializationSummary(), wordSummary: await getWordsSummary(), workers: await getWorkerHeartbeats() });
  } catch (error) { return internalError(error, "获取初始化状态失败。"); }
}
