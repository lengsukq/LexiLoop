import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { updateManualDefinition } from "@/modules/words/service";
import { z } from "zod";

export async function PUT(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await context.params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。");
    return ok(await updateManualDefinition(id, await request.json()));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "手动释义参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    return internalError(error, "保存手动释义失败。");
  }
}
