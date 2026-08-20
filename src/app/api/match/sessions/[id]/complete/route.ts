import { createCompleteHandler } from "@/lib/route-factory";
import { completeMatchingSession } from "@/modules/matching/service";
import { MAX_ACTIVE_ANSWER_DURATION_MS } from "@/modules/reviews/duration";
import { HOUR_MS } from "@/lib/time";
import { z } from "zod";

const schema = z.object({
  results: z.array(z.object({
    itemId: z.number().int().positive(),
    wordId: z.number().int().positive(),
    matched: z.boolean(),
    hadMistake: z.boolean(),
    durationMs: z.number().int().min(0).max(MAX_ACTIVE_ANSWER_DURATION_MS).optional(),
  })).max(8),
  elapsedMs: z.number().int().min(0).max(HOUR_MS),
  durationSeconds: z.number().int().min(30).max(180),
  mistakeCount: z.number().int().min(0).max(1000),
  maxCombo: z.number().int().min(0).max(1000),
});

export const dynamic = "force-dynamic";
export const POST = createCompleteHandler({
  schema,
  complete: completeMatchingSession,
  idErrorMessage: "配对会话 ID 无效。",
  validationMessage: "配对结果参数无效。",
  fallbackMessage: "保存词汇配对结果失败。",
});
