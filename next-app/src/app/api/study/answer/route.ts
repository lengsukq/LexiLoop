import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { QUESTION_TYPES, REVIEW_RATINGS } from "@/lib/types";
import { MAX_ACTIVE_ANSWER_DURATION_MS } from "@/modules/reviews/duration";
import { processReviewAnswer } from "@/modules/reviews/service";
import { z } from "zod";
const schema = z.object({
  clientAnswerId: z.string().min(8).max(128),
  wordId: z.number().int().positive(),
  studySessionId: z.number().int().positive().optional(),
  studySessionItemId: z.number().int().positive().optional(),
  rating: z.enum(REVIEW_RATINGS),
  questionType: z.enum(QUESTION_TYPES),
  userAnswer: z.string().max(1000).optional(),
  durationMs: z.number().int().min(0).max(MAX_ACTIVE_ANSWER_DURATION_MS).optional(),
});
export async function POST(request: NextRequest) {
  try { return ok(await processReviewAnswer(schema.parse(await request.json()))); }
  catch (error) {
    return handleRouteError(error, { validationMessage: "答案参数无效。", fallbackMessage: "提交学习答案失败。" });
  }
}
