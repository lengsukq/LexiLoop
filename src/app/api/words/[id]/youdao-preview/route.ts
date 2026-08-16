import type { NextRequest } from "next/server";
import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { previewYoudaoContent } from "@/modules/words/youdao-refresh";
import { z } from "zod";

const schema = z.object({
  term: z.string().trim().min(1).max(300).optional(),
}).strict();

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const input = schema.parse(await request.json().catch(() => ({})));
    return ok(await previewYoudaoContent(id, input.term));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "参数无效。", fallbackMessage: "有道词典获取失败。" });
  }
}
