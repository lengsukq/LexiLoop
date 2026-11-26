import { ok, internalError, parsePositiveInt } from "@/lib/api";
import { listImportBatches } from "@/modules/imports/service";
import type { NextRequest } from "next/server";
export const dynamic = "force-dynamic";
export async function GET(request: NextRequest) { try { return ok(await listImportBatches(parsePositiveInt(request.nextUrl.searchParams.get("limit"), 50, 100))); } catch (error) { return internalError(error, "获取导入历史失败。"); } }
