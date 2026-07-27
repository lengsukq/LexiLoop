import type { NextRequest } from "next/server";
import { internalError, ok, parsePositiveInt } from "@/lib/api";
import { INITIALIZATION_STATUSES, type InitializationStatus } from "@/lib/types";
import { listInitializationJobs } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  try {
    const searchParams = request.nextUrl.searchParams;
    const rawStatus = searchParams.get("status");
    const status = rawStatus && INITIALIZATION_STATUSES.includes(rawStatus as InitializationStatus)
      ? (rawStatus as InitializationStatus)
      : undefined;
    const page = parsePositiveInt(searchParams.get("page"), 1, 1000);
    const pageSize = Math.min(parsePositiveInt(searchParams.get("pageSize"), 50, 50), 200);
    const search = searchParams.get("search") || undefined;
    const result = await listInitializationJobs({ page, pageSize, status, search });
    return ok(result);
  } catch (error) {
    return internalError(error, "获取初始化任务失败。");
  }
}
