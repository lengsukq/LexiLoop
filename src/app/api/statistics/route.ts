import type { NextRequest } from "next/server";
import { internalError, ok, parsePositiveInt } from "@/lib/api";
import { getStatistics } from "@/modules/statistics/service";
export const dynamic = "force-dynamic";
export async function GET(request: NextRequest) { try { return ok(await getStatistics(parsePositiveInt(request.nextUrl.searchParams.get("days"), 30, 365))); } catch (error) { return internalError(error, "获取学习统计失败。"); } }
