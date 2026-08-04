import { internalError, ok } from "@/lib/api";
import { runBackgroundTick } from "@/modules/background/tick";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

/**
 * 手动触发一轮后台处理：在时间预算内循环处理初始化任务，用于在
 * serverless 环境（无常驻 Worker）下手动推进积压的初始化队列。
 */
export async function POST() {
  try {
    const result = await runBackgroundTick({ maxJobs: 3, timeBudgetMs: 50_000 });
    return ok(result);
  } catch (error) {
    return internalError(error, "启动初始化处理失败。");
  }
}
