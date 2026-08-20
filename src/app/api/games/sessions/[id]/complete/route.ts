import { createCompleteHandler } from "@/lib/route-factory";
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
export const POST = createCompleteHandler({
  schema,
  complete: completeGameSession,
  idErrorMessage: "小游戏会话 ID 无效。",
  validationMessage: "小游戏结果参数无效。",
  fallbackMessage: "保存小游戏结果失败。",
});
