import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { MAX_CSV_BYTES, MAX_CSV_ROWS } from "@/lib/config";
import { createImportPreview } from "@/modules/imports/service";
export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    const form = await request.formData();
    const file = form.get("file");
    if (!(file instanceof File)) return fail("CSV_REQUIRED", "请选择 EasyDict CSV 文件。");
    if (!file.name.toLowerCase().endsWith(".csv")) return fail("CSV_TYPE_INVALID", "仅支持 .csv 文件。");
    if (file.size > MAX_CSV_BYTES) return fail("CSV_TOO_LARGE", "CSV 文件不能超过 10MB。");
    const content = await file.text();
    const approximateRows = content.split(/\r?\n/).length - 1;
    if (approximateRows > MAX_CSV_ROWS) return fail("CSV_TOO_MANY_ROWS", "CSV 不能超过 20,000 行。");
    return ok(await createImportPreview(content, file.name));
  } catch (error) {
    if (error instanceof Error && /缺少必要列|UTF-8|CSV/.test(error.message)) return fail("CSV_INVALID", error.message);
    return internalError(error, "生成导入预览失败。");
  }
}
