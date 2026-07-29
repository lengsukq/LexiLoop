import type { NextRequest } from "next/server";
import { z } from "zod";
import { fail, internalError, ok } from "@/lib/api";
import { deleteExample } from "@/modules/words/service";

export async function DELETE(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await context.params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。");
    return ok(deleteExample(id, await request.json()));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "例句参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "EXAMPLE_NOT_FOUND") return fail("EXAMPLE_NOT_FOUND", "例句不存在。", 404);
    return internalError(error, "删除例句失败。");
  }
}
