import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { createImportPreviewFromFile } from "@/modules/imports/preview-file";

export const runtime = "nodejs";

export async function POST(request: NextRequest) {
  try {
    const form = await request.formData();
    return ok(await createImportPreviewFromFile(form.get("file")));
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "生成导入预览失败。" });
  }
}
