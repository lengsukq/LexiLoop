import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { getStudySession } from "@/modules/study/service";
export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try { const id = Number((await context.params).id); if (!Number.isInteger(id) || id <= 0) return fail("SESSION_ID_INVALID", "会话 ID 无效。"); return ok(getStudySession(id)); }
  catch (error) { if (error instanceof Error && error.message === "STUDY_SESSION_NOT_FOUND") return fail("SESSION_NOT_FOUND", "学习会话不存在。", 404); return internalError(error, "获取学习会话失败。"); }
}
