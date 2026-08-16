import type { NextRequest } from "next/server";
import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { getStudySession } from "@/modules/study/service";

export async function GET(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "SESSION_ID_INVALID", "会话 ID 无效。");
    return ok(await getStudySession(id));
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "获取学习会话失败。" });
  }
}
