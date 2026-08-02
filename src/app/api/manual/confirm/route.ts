import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { confirmManualPreview, ManualPreviewError } from "@/modules/manual/service";
import { z } from "zod";

export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    return ok(await confirmManualPreview(await request.json()));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "预览令牌无效。", 400, error.issues);
    if (error instanceof ManualPreviewError) {
      const status = error.code === "MANUAL_PREVIEW_NOT_FOUND" ? 404 : error.code === "MANUAL_PREVIEW_EXPIRED" ? 410 : 409;
      return fail(error.code, error.message, status, error.details);
    }
    return internalError(error, "确认添加失败。");
  }
}
