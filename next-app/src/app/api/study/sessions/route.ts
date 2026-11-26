import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { STUDY_MODES } from "@/lib/types";
import { startStudySession } from "@/modules/study/service";
import { z } from "zod";
const schema = z.object({ mode: z.enum(STUDY_MODES).default("DAILY"), resume: z.boolean().default(true), continuous: z.boolean().default(false) });
export async function POST(request: NextRequest) {
  try { const { mode, resume, continuous } = schema.parse(await request.json().catch(() => ({}))); return ok(await startStudySession(mode, resume, continuous)); }
  catch (error) {
    return handleRouteError(error, { validationMessage: "学习模式无效。", fallbackMessage: "创建学习会话失败。" });
  }
}
