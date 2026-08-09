import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { completeGameSession, GAME_MODES } from "@/modules/games/service";
import { MAX_ACTIVE_ANSWER_DURATION_MS } from "@/modules/reviews/duration";
import { HOUR_MS } from "@/lib/time";
import { z } from "zod";

const schema = z.object({
  mode: z.enum(GAME_MODES),
  answers: z.array(z.object({
    itemId: z.number().int().positive(),
    wordId: z.number().int().positive(),
    solved: z.boolean(),
    hadMistake: z.boolean(),
    durationMs: z.number().int().min(0).max(MAX_ACTIVE_ANSWER_DURATION_MS).optional(),
  })).max(20),
  elapsedMs: z.number().int().min(0).max(HOUR_MS),
  mistakeCount: z.number().int().min(0).max(1000),
  maxCombo: z.number().int().min(0).max(1000),
});

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await context.params;
    const sessionId = Number(id);
    if (!Number.isInteger(sessionId) || sessionId <= 0) return fail("VALIDATION_ERROR", "小游戏会话 ID 无效。", 400);
    const input = schema.parse(await request.json());
    return ok(await completeGameSession({ sessionId, ...input }));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "小游戏结果参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "GAME_SESSION_NOT_FOUND") {
      return fail("GAME_SESSION_NOT_FOUND", "小游戏会话不存在或已经失效。", 404);
    }
    return internalError(error, "保存小游戏结果失败。");
  }
}
