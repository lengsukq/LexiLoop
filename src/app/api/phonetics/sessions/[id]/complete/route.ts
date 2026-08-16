import { NextRequest } from "next/server";
import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { completePhoneticGame } from "@/modules/phonetics/service";
import { MAX_ACTIVE_ANSWER_DURATION_MS } from "@/modules/reviews/duration";
import { HOUR_MS } from "@/lib/time";
import { z } from "zod";

const schema = z.object({
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
    const sessionId = requireRouteId((await context.params).id, "VALIDATION_ERROR", "音标训练会话 ID 无效。");
    const input = schema.parse(await request.json());
    return ok(await completePhoneticGame({ sessionId, ...input }));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "音标训练结果参数无效。", fallbackMessage: "保存音标训练结果失败。" });
  }
}
