import { fail } from "@/lib/api";
export const runtime = "nodejs";
export async function POST() {
  return fail("SQLITE_RESTORE_UNAVAILABLE", "当前为 PostgreSQL 模式，SQLite 文件恢复不可用。请使用 JSON 备份。", 501);
}
