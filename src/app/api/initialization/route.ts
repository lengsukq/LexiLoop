import type { NextRequest } from "next/server";
import { internalError, ok, parsePositiveInt } from "@/lib/api";
import { INITIALIZATION_STATUSES, type InitializationStatus } from "@/lib/types";
import { listInitializationJobs } from "@/modules/initialization/service";
export const dynamic = "force-dynamic";
export async function GET(request: NextRequest) {
  try {
    const raw = request.nextUrl.searchParams.get("status");
    const status = raw && INITIALIZATION_STATUSES.includes(raw as InitializationStatus) ? raw as InitializationStatus : undefined;
    return ok(await listInitializationJobs(parsePositiveInt(request.nextUrl.searchParams.get("limit"), 100, 500), status));
  } catch (error) { return internalError(error, "获取初始化任务失败。"); }
}
