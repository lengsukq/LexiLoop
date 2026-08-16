import type { NextRequest } from "next/server";
import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { updateManualDefinition } from "@/modules/words/service";

export async function PUT(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    return ok(await updateManualDefinition(id, await request.json()));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "手动释义参数无效。", fallbackMessage: "保存手动释义失败。" });
  }
}
