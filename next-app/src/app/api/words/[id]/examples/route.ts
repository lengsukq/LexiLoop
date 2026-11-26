import type { NextRequest } from "next/server";
import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { deleteExample } from "@/modules/words/service";

export async function DELETE(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    return ok(await deleteExample(id, await request.json()));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "例句参数无效。", fallbackMessage: "删除例句失败。" });
  }
}
