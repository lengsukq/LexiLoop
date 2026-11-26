import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { createManualPreview, ManualPreviewError } from "@/modules/manual/service";
import { z } from "zod";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    return ok(await createManualPreview(await request.json()));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "输入内容或语言参数无效。", 400, error.issues);
    if (error instanceof ManualPreviewError) return fail(error.code, error.message, 422, error.details);
    return internalError(error, "生成 AI 预览失败。");
  }
}
