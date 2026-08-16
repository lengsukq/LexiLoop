import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
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
    return ok(await skipStudyItem(input.studySessionId, input.studySessionItemId, input.reason));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "跳过参数无效。", fallbackMessage: "跳过学习题目失败。" });
  }
}
