import { internalError } from "@/lib/api";
import { createJsonBackup } from "@/modules/backups/service";
export async function GET() {
  try {
    const filename = `lexiloop-${new Date().toISOString().slice(0, 10)}.json`;
    return new Response(JSON.stringify(createJsonBackup(), null, 2), { headers: { "Content-Type": "application/json; charset=utf-8", "Content-Disposition": `attachment; filename="${filename}"`, "Cache-Control": "no-store" } });
  } catch (error) { return internalError(error, "导出 JSON 备份失败。"); }
}
