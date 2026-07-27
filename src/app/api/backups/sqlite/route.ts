import fs from "node:fs/promises";
import { internalError } from "@/lib/api";
import { createSqliteBackup, removeGeneratedBackup } from "@/modules/backups/service";
export const runtime = "nodejs";
export async function GET() {
  let backup: Awaited<ReturnType<typeof createSqliteBackup>> | null = null;
  try {
    backup = await createSqliteBackup();
    const buffer = await fs.readFile(backup.path);
    return new Response(buffer, { headers: { "Content-Type": "application/vnd.sqlite3", "Content-Disposition": `attachment; filename="${backup.filename}"`, "Cache-Control": "no-store" } });
  } catch (error) {
    return internalError(error, "导出 SQLite 备份失败。");
  } finally {
    if (backup) removeGeneratedBackup(backup.path);
  }
}
