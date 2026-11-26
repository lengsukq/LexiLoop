import type { NextRequest } from "next/server";
import { fail, handleRouteError, ok, requireRouteId } from "@/lib/api";
import { deleteWord, getWordDetail, updateWord } from "@/modules/words/service";

export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const word = await getWordDetail(id);
    return word ? ok(word) : fail("WORD_NOT_FOUND", "词条不存在。", 404);
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "获取词条详情失败。" });
  }
}

export async function PATCH(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    return ok(await updateWord(id, await request.json()));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "词条更新参数无效。", fallbackMessage: "更新词条失败。" });
  }
}

export async function DELETE(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const force = request.nextUrl.searchParams.get("force") === "true";
    return (await deleteWord(id, force)) ? ok({ deleted: true }) : fail("WORD_NOT_FOUND", "词条不存在。", 404);
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "删除词条失败。" });
  }
}
