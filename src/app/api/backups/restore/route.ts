import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { stageSqliteRestore } from "@/modules/backups/service";
export const runtime = "nodejs";
export async function POST(request: NextRequest) {
  try {
    const form = await request.formData(); const file = form.get("file");
    if (!(file instanceof File)) return fail("FILE_REQUIRED", "请选择 LexiLoop SQLite 备份。");
    if (file.size > 1024 * 1024 * 1024) return fail("FILE_TOO_LARGE", "备份文件不能超过 1GB。");
    const staged = stageSqliteRestore(Buffer.from(await file.arrayBuffer()));
    const migrationMessage = staged.pendingMigrations.length
      ? `恢复后会自动执行 ${staged.pendingMigrations.length} 个数据库迁移。`
      : "备份结构与当前版本一致。";
    return ok({ ...staged, restartRequired: true, message: `备份已校验并暂存。${migrationMessage} 重启 app 和 worker 容器后自动恢复。` });
  } catch (error) { return internalError(error, error instanceof Error ? error.message : "恢复备份失败。"); }
}
