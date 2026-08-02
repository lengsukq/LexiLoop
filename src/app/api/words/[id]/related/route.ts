import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { addRelatedWord, previewRelatedWord } from "@/modules/words/service";
import { z } from "zod";

function parseId(value: string): number | null {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : null;
}

export async function GET(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = parseId((await context.params).id);
    if (!id) return fail("WORD_ID_INVALID", "词条 ID 无效。");
    const term = request.nextUrl.searchParams.get("term")?.trim();
    if (!term) return fail("RELATED_TERM_REQUIRED", "请选择关联词。");
    return ok(await previewRelatedWord(id, term));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "关联词参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    if (error instanceof Error && error.message === "RELATED_WORD_SAME_AS_PARENT") return fail("RELATED_WORD_SAME_AS_PARENT", "不能把当前词条再次加入词库。", 409);
    return internalError(error, "获取关联词状态失败。");
  }
}

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = parseId((await context.params).id);
    if (!id) return fail("WORD_ID_INVALID", "词条 ID 无效。");
    return ok(await addRelatedWord(id, await request.json()));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "关联词参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    if (error instanceof Error && error.message === "RELATED_WORD_SAME_AS_PARENT") return fail("RELATED_WORD_SAME_AS_PARENT", "不能把当前词条再次加入词库。", 409);
    return internalError(error, "加入关联词失败。");
  }
}
