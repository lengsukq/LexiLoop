import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { skipStudyItem } from "@/modules/study/service";
import { z } from "zod";

const schema = z.object({
  studySessionId: z.number().int().positive(),
  studySessionItemId: z.number().int().positive(),
  reason: z.enum(["LATER", "NO_AUDIO", "CONTENT_ISSUE"]).default("LATER"),
});

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    return ok(skipStudyItem(input.studySessionId, input.studySessionItemId, input.reason));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "跳过参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "STUDY_ITEM_NOT_FOUND") return fail("STUDY_ITEM_NOT_FOUND", "学习题目不存在。", 404);
    if (error instanceof Error && error.message === "STUDY_ITEM_ALREADY_PROCESSED") return fail("STUDY_ITEM_ALREADY_PROCESSED", "该题目已经处理，不能重复跳过。", 409);
    return internalError(error, "跳过学习题目失败。");
  }
}
