import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { IMPORT_MODES } from "@/lib/types";
import { commitImport } from "@/modules/imports/service";
import { z } from "zod";
const schema = z.object({ previewToken: z.string().uuid(), mode: z.enum(IMPORT_MODES), resetLearningProgress: z.boolean().default(false) });
export async function POST(request: NextRequest) {
  try { const input = schema.parse(await request.json()); return ok(commitImport(input.previewToken, input.mode, input.resetLearningProgress)); }
  catch (error) {
    if (error instanceof Error && error.message === "IMPORT_PREVIEW_EXPIRED") return fail("IMPORT_PREVIEW_EXPIRED", "导入预览已过期，请重新上传。", 409);
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "导入参数无效。", 400, error.issues);
    return internalError(error, "提交导入失败。");
  }
}
