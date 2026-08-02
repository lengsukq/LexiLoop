import { fail } from "@/lib/api";
export const runtime = "nodejs";
export async function GET() {
  return fail("SQLITE_BACKUP_UNAVAILABLE", "当前为 PostgreSQL 模式，SQLite 文件备份不可用。请使用 JSON 备份。", 501);
}
