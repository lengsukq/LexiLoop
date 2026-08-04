import type { NextRequest } from "next/server";
import { fail, ok, internalError } from "@/lib/api";
import { runBackgroundTick, SERVERLESS_WORKER_ID } from "@/modules/background/tick";

export const dynamic = "force-dynamic";
export const maxDuration = 60;

function isAuthorized(request: NextRequest): boolean {
  // Vercel Cron 自动附带该请求头；自托管/本地兜底可配置 CRON_SECRET 后用 Bearer 调用。
  if (request.headers.get("x-vercel-cron") === "1") return true;
  const secret = process.env.CRON_SECRET;
  return Boolean(secret && request.headers.get("authorization") === `Bearer ${secret}`);
}

export async function GET(request: NextRequest) {
  if (!isAuthorized(request)) {
    return fail("UNAUTHORIZED", "未授权的后台任务请求。", 401);
  }
  try {
    const result = await runBackgroundTick({ maxJobs: 5, workerId: SERVERLESS_WORKER_ID });
    return ok(result);
  } catch (error) {
    return internalError(error, "后台任务执行失败。");
  }
}
