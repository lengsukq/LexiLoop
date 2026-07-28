import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { completeMatchingSession } from "@/modules/matching/service";
import { z } from "zod";

const schema = z.object({
  results: z.array(z.object({
    itemId: z.number().int().positive(),
    wordId: z.number().int().positive(),
    matched: z.boolean(),
    hadMistake: z.boolean(),
    durationMs: z.number().int().min(0).max(60 * 60 * 1000).optional(),
  })).max(8),
  elapsedMs: z.number().int().min(0).max(60 * 60 * 1000),
  durationSeconds: z.number().int().min(30).max(180),
  mistakeCount: z.number().int().min(0).max(1000),
  maxCombo: z.number().int().min(0).max(1000),
});

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await context.params;
    const sessionId = Number(id);
    if (!Number.isInteger(sessionId) || sessionId <= 0) return fail("VALIDATION_ERROR", "配对会话 ID 无效。", 400);
    const input = schema.parse(await request.json());
    return ok(await completeMatchingSession({ sessionId, ...input }));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "配对结果参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "MATCH_SESSION_NOT_FOUND") {
      return fail("MATCH_SESSION_NOT_FOUND", "配对会话不存在或已经失效。", 404);
    }
    return internalError(error, "保存词汇配对结果失败。");
  }
}
