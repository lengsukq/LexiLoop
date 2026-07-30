import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { STUDY_MODES } from "@/lib/types";
import { startStudySession } from "@/modules/study/service";
import { z } from "zod";
const schema = z.object({ mode: z.enum(STUDY_MODES).default("DAILY"), resume: z.boolean().default(true), continuous: z.boolean().default(false) });
export async function POST(request: NextRequest) {
  try { const { mode, resume, continuous } = schema.parse(await request.json().catch(() => ({}))); return ok(await startStudySession(mode, resume, continuous)); }
  catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "学习模式无效。", 400, error.issues);
    if (error instanceof Error && error.message === "AI_RECOMMENDED_ALL_DONE") return fail("AI_RECOMMENDED_ALL_DONE", "今日 AI 必做题已全部完成，明天再来吧。", 409);
    return internalError(error, "创建学习会话失败。");
  }
}
