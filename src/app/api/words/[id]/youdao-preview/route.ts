import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { previewYoudaoContent } from "@/modules/words/youdao-refresh";
import { z } from "zod";

const schema = z.object({
  term: z.string().trim().min(1).max(300).optional(),
}).strict();

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await context.params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。", 400);
    const input = schema.parse(await request.json().catch(() => ({})));
    return ok(await previewYoudaoContent(id, input.term));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    return internalError(error, "有道词典获取失败。");
  }
}
