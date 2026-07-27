import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { deleteWord, getWordDetail, updateWord } from "@/modules/words/service";
import { z } from "zod";
function parseId(value: string) { const id = Number(value); return Number.isInteger(id) && id > 0 ? id : null; }
export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try { const id = parseId((await context.params).id); if (!id) return fail("WORD_ID_INVALID", "词条 ID 无效。"); const word = getWordDetail(id); return word ? ok(word) : fail("WORD_NOT_FOUND", "词条不存在。", 404); }
  catch (error) { return internalError(error, "获取词条详情失败。"); }
}
export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try { const id = parseId((await context.params).id); if (!id) return fail("WORD_ID_INVALID", "词条 ID 无效。"); return ok(updateWord(id, await request.json())); }
  catch (error) { if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "词条更新参数无效。", 400, error.issues); if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404); return internalError(error, "更新词条失败。"); }
}
export async function DELETE(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try { const id = parseId((await context.params).id); if (!id) return fail("WORD_ID_INVALID", "词条 ID 无效。"); return deleteWord(id) ? ok({ deleted: true }) : fail("WORD_NOT_FOUND", "词条不存在。", 404); }
  catch (error) {
    if (error instanceof Error && error.message === "WORD_HAS_LEARNING_HISTORY") return fail("WORD_HAS_LEARNING_HISTORY", "该词条已有学习记录，不能硬删除。请改为暂停学习。", 409);
    return internalError(error, "删除词条失败。");
  }
}
