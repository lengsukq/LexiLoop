import { handleRouteError, ok } from "@/lib/api";
import { restoreJsonBackup } from "@/modules/backups/service";

export const runtime = "nodejs";
export const maxDuration = 60;

// Larger backups (current Queen export ~20MB) exceed the default middleware/FormData body limit.
// The limit is raised via next.config.ts `experimental.proxyClientMaxBodySize` for self-hosted/Queen builds.

export async function POST(request: Request) {
  try {
    let raw: string | null = null;

    // Prefer JSON body (no FormData overhead, avoids multipart boundary issues for large payloads).
    const contentType = request.headers.get("content-type") ?? "";
    if (contentType.includes("application/json")) {
      const body = (await request.json().catch(() => null)) as { raw?: unknown } | null;
      if (typeof body?.raw === "string") raw = body.raw;
      // Also handle case where the entire JSON file is posted as body
      else if (body && typeof body === "object" && "format" in body && (body as Record<string, unknown>).format === "lexiloop-json-backup") {
        raw = JSON.stringify(body);
      }
    }

    // Fallback: multipart FormData with `file` field (Settings UI flow).
    if (raw === null) {
      const formData = await request.formData();
      const file = formData.get("file");
      if (file instanceof File) {
        if (file.size === 0) return ok({ message: "备份文件为空。" }, { status: 400 });
        raw = await file.text();
      } else if (typeof file === "string") {
        raw = file;
      }
    }

    if (!raw) return ok({ message: "请上传备份文件（FormData file 或 JSON raw）。" }, { status: 400 });
    if (raw.length === 0) return ok({ message: "备份文件为空。" }, { status: 400 });

    const result = await restoreJsonBackup(raw);
    const totalRows = Object.values(result.rowCounts).reduce((a, b) => a + b, 0);
    return ok({
      message: `恢复成功，共 ${totalRows} 行（${Object.entries(result.rowCounts)
        .filter(([, n]) => n > 0)
        .map(([k, n]) => `${k}:${n}`)
        .join(", ")}）。`,
      rowCounts: result.rowCounts,
    });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "恢复失败。", validationMessage: "备份文件无效。" });
  }
}
