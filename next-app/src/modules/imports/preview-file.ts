import { ApiError } from "@/lib/api-errors";
import { MAX_CSV_BYTES, MAX_CSV_ROWS } from "@/lib/config";
import { createImportPreview } from "./service";

export async function createImportPreviewFromFile(file: unknown) {
  if (!(file instanceof File)) {
    throw new ApiError("CSV_REQUIRED", "请选择 EasyDict CSV 文件。", 400);
  }
  if (!file.name.toLowerCase().endsWith(".csv")) {
    throw new ApiError("CSV_TYPE_INVALID", "仅支持 .csv 文件。", 400);
  }
  if (file.size > MAX_CSV_BYTES) {
    throw new ApiError("CSV_TOO_LARGE", "CSV 文件不能超过 10MB。", 400);
  }
  const content = await file.text();
  const approximateRows = content.split(/\r?\n/).length - 1;
  if (approximateRows > MAX_CSV_ROWS) {
    throw new ApiError("CSV_TOO_MANY_ROWS", "CSV 不能超过 20,000 行。", 400);
  }
  try {
    return await createImportPreview(content, file.name);
  } catch (error) {
    if (error instanceof Error && /缺少必要列|UTF-8|CSV/.test(error.message)) {
      throw new ApiError("CSV_INVALID", error.message, 400);
    }
    throw error;
  }
}
