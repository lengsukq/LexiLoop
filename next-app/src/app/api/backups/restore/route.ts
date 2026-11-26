import { handleRouteError, ok } from "@/lib/api";
import {
  extractBackupRawFromFormData,
  extractBackupRawFromJson,
  restoreBackupWithSummary,
} from "@/modules/backups/restore-request";

export const runtime = "nodejs";
export const maxDuration = 60;

export async function POST(request: Request) {
  try {
    let raw: string | null = null;
    let emptyFile = false;

    const contentType = request.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      const body = await request.json().catch(() => null);
      raw = await extractBackupRawFromJson(body);
    }

    if (raw === null) {
      const formData = await request.formData();
      const extracted = await extractBackupRawFromFormData(formData);
      raw = extracted.raw;
      emptyFile = Boolean(extracted.emptyFile);
    }

    const result = await restoreBackupWithSummary(raw, emptyFile);
    return ok(result.body, { status: result.status });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "恢复失败。", validationMessage: "备份文件无效。" });
  }
}
