import type { NextRequest } from "next/server";
import { internalError, ok, parsePositiveInt } from "@/lib/api";
import { INITIALIZATION_STATUSES, MASTERY_LEVELS, type InitializationStatus, type MasteryLevel } from "@/lib/types";
import { listWords } from "@/modules/words/service";
export const dynamic = "force-dynamic";
export async function GET(request: NextRequest) {
  try {
    const p = request.nextUrl.searchParams;
    const rawStatus = p.get("status");
    const rawMastery = p.get("mastery");
    const rawSort = p.get("sort");
    const rawOrder = p.get("order");
    return ok(listWords({
      query: p.get("q")?.trim() || undefined,
      status: rawStatus && INITIALIZATION_STATUSES.includes(rawStatus as InitializationStatus) ? rawStatus as InitializationStatus : undefined,
      mastery: rawMastery && MASTERY_LEVELS.includes(rawMastery as MasteryLevel) ? rawMastery as MasteryLevel : undefined,
      wrong: p.get("wrong") === "true",
      due: p.get("due") === "true",
      suspended: p.has("suspended") ? p.get("suspended") === "true" : undefined,
      page: parsePositiveInt(p.get("page"), 1, 100_000),
      limit: parsePositiveInt(p.get("limit"), 50, 200),
      sort: ["createdAt", "term", "masteryScore", "sourceCreatedAt", "dueAt"].includes(rawSort ?? "") ? rawSort as "createdAt" | "term" | "masteryScore" | "sourceCreatedAt" | "dueAt" : "createdAt",
      order: rawOrder === "asc" ? "asc" : "desc",
    }));
  } catch (error) { return internalError(error, "获取词条列表失败。"); }
}
