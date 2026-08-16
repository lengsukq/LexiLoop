import { ok, internalError } from "@/lib/api";
import { runBackgroundTick } from "@/modules/background/tick";
import { getInitializationSummary } from "@/modules/initialization/service";
export const dynamic = "force-dynamic";
// AI 初始化单个任务可能超过 Hobby 计划默认 10 秒超时，放宽以免任务处理到一半被冻结。
export const maxDuration = 60;
export async function GET() {
  try {
    // 该接口被全局常驻的 BackgroundKeepalive 组件轮询，使初始化队列在用户停留在任意页面时都能持续推进，
    // 不再依赖初始化页面的轮询；返回排队任务数供客户端自适应调整轮询频率。
    const result = await runBackgroundTick({ maxJobs: 3 });
    const summary = await getInitializationSummary();
    const queued = summary.QUEUED + summary.PENDING + summary.RUNNING;
    return ok({ running: queued > 0, queued, claimed: result.claimed, elapsedMs: result.elapsedMs });
  } catch (error) { return internalError(error, "后台保活失败。"); }
}
