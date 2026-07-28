import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { completePhoneticGame } from "@/modules/phonetics/service";
import { z } from "zod";

const schema = z.object({
  answers: z.array(z.object({
    itemId: z.number().int().positive(),
    wordId: z.number().int().positive(),
    solved: z.boolean(),
    hadMistake: z.boolean(),
    durationMs: z.number().int().min(0).max(60 * 60 * 1000).optional(),
  })).max(20),
  elapsedMs: z.number().int().min(0).max(60 * 60 * 1000),
  mistakeCount: z.number().int().min(0).max(1000),
  maxCombo: z.number().int().min(0).max(1000),
});

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await context.params;
    const sessionId = Number(id);
    if (!Number.isInteger(sessionId) || sessionId <= 0) {
      return fail("VALIDATION_ERROR", "音标训练会话 ID 无效。", 400);
    }
    const input = schema.parse(await request.json());
    return ok(await completePhoneticGame({ sessionId, ...input }));
  } catch (error) {
    if (error instanceof z.ZodError) {
      return fail("VALIDATION_ERROR", "音标训练结果参数无效。", 400, error.issues);
    }
    if (error instanceof Error && error.message === "PHONETIC_SESSION_NOT_FOUND") {
      return fail("PHONETIC_SESSION_NOT_FOUND", "音标训练会话不存在或已经失效。", 404);
    }
    return internalError(error, "保存音标训练结果失败。");
  }
}
