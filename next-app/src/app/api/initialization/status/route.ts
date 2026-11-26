import { ok, internalError } from "@/lib/api";
import { getInitializationSummary, getWordsSummary, getWorkerHeartbeats } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";
export async function GET() {
  try {
    // 纯状态查询：初始化队列的推进由全局 BackgroundKeepalive 轮询的 /api/background/keepalive 承担，
    // 这里不再顺带执行 tick，避免每次状态刷新重复触发后台任务。
    return ok({ summary: await getInitializationSummary(), wordSummary: await getWordsSummary(), workers: await getWorkerHeartbeats() });
  } catch (error) { return internalError(error, "获取初始化状态失败。"); }
}
