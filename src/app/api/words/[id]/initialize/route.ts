import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { queueWordInitialization } from "@/modules/initialization/service";
export async function POST(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try { const id = Number((await context.params).id); if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。"); return ok({ jobId: queueWordInitialization(id), queued: true }); }
  catch (error) { if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404); return internalError(error, "创建初始化任务失败。"); }
}
