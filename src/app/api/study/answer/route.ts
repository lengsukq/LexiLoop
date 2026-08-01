import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
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
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "答案参数无效。", 400, error.issues);
    if (error instanceof Error) {
      const messages: Record<string, string> = {
        WORD_NOT_FOUND: "词条不存在。",
        WORD_NOT_READY: "词条尚未初始化完成。",
        WORD_SUSPENDED: "词条已暂停学习。",
        INVALID_STUDY_CONTEXT: "学习会话和题目参数必须同时提供。",
        STUDY_ITEM_NOT_FOUND: "学习题目不存在。",
        STUDY_ITEM_ALREADY_PROCESSED: "该题目已经处理，不能重复提交。",
        STUDY_ITEM_WORD_MISMATCH: "提交的词条与学习题目不匹配。",
        STUDY_ITEM_QUESTION_MISMATCH: "提交的题型与学习题目不匹配。",
        IDEMPOTENCY_KEY_CONFLICT: "该答案请求标识已被其他提交使用。",
      };
      const message = messages[error.message];
      if (message) return fail(error.message, message, error.message === "STUDY_ITEM_NOT_FOUND" ? 404 : 409);
    }
    return internalError(error, "提交学习答案失败。");
  }
}
