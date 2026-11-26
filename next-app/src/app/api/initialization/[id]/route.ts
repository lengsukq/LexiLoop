import { NextRequest } from "next/server";
import { fail, handleRouteError, ok, requireRouteId } from "@/lib/api";
import { getJobDetails } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const jobId = requireRouteId((await params).id, "JOB_ID_INVALID", "任务 ID 无效。");
    const details = await getJobDetails(jobId);
    return details ? ok(details) : fail("JOB_NOT_FOUND", "任务不存在。", 404);
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "获取任务详情失败。" });
  }
}
