import type { NextRequest } from "next/server";
import { fail, handleRouteError, ok, requireRouteId } from "@/lib/api";
import { addRelatedWord, previewRelatedWord } from "@/modules/words/service";

export async function GET(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const term = request.nextUrl.searchParams.get("term")?.trim();
    if (!term) return fail("RELATED_TERM_REQUIRED", "请选择关联词。");
    return ok(await previewRelatedWord(id, term));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "关联词参数无效。", fallbackMessage: "获取关联词状态失败。" });
  }
}

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    return ok(await addRelatedWord(id, await request.json()));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "关联词参数无效。", fallbackMessage: "加入关联词失败。" });
  }
}
