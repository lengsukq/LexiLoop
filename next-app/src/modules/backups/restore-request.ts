import { restoreJsonBackup } from "./service";

export type RestoreOutcome =
  | { status: 200; body: { message: string; rowCounts: Record<string, number> } }
  | { status: 400; body: { message: string } };

export async function extractBackupRawFromJson(body: unknown): Promise<string | null> {
  if (body && typeof body === "object") {
    const record = body as Record<string, unknown>;
    if (typeof record.raw === "string") return record.raw;
    if ("format" in record && record.format === "lexiloop-json-backup") {
      return JSON.stringify(body);
    }
  }
  return null;
}

export async function extractBackupRawFromFormData(formData: FormData): Promise<{ raw: string | null; emptyFile?: boolean }> {
  const file = formData.get("file");
  if (file instanceof File) {
    if (file.size === 0) return { raw: null, emptyFile: true };
    return { raw: await file.text() };
  }
  if (typeof file === "string") {
    return { raw: file };
  }
  return { raw: null };
}

export async function restoreBackupWithSummary(raw: string | null, emptyFile = false): Promise<RestoreOutcome> {
  if (emptyFile) return { status: 400, body: { message: "备份文件为空。" } };
  if (!raw) return { status: 400, body: { message: "请上传备份文件（FormData file 或 JSON raw）。" } };
  if (raw.length === 0) return { status: 400, body: { message: "备份文件为空。" } };

  const result = await restoreJsonBackup(raw);
  const totalRows = Object.values(result.rowCounts).reduce((a, b) => a + b, 0);
  return {
    status: 200,
    body: {
      message: `恢复成功，共 ${totalRows} 行（${Object.entries(result.rowCounts)
        .filter(([, n]) => n > 0)
        .map(([k, n]) => `${k}:${n}`)
        .join(", ")}）。`,
      rowCounts: result.rowCounts,
    },
  };
}
