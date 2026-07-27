import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { isAdminAuthorized } from "@/lib/security";
import { downloadAndInstallEcdict, getEcdictStatus, installUploadedEcdict, removeEcdict, setEcdictEnabled } from "@/modules/ecdict/service";
import { z } from "zod";
const actionSchema = z.object({ action: z.enum(["download", "enable", "disable"]) });
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export async function GET() { try { return ok(await getEcdictStatus()); } catch (error) { return internalError(error, "获取 ECDICT 状态失败。"); } }
export async function POST(request: NextRequest) {
  if (!isAdminAuthorized(request)) return fail("UNAUTHORIZED", "管理令牌无效。", 401);
  try {
    const { action } = actionSchema.parse(await request.json());
    if (action === "download") return ok(await downloadAndInstallEcdict());
    return ok(await setEcdictEnabled(action === "enable"));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "ECDICT 操作无效。", 400, error.issues);
    if (error instanceof Error && error.message === "ECDICT_NOT_INSTALLED") return fail("ECDICT_NOT_INSTALLED", "请先安装或上传 ECDICT。", 409);
    return internalError(error, "执行 ECDICT 操作失败。");
  }
}
export async function PUT(request: NextRequest) {
  if (!isAdminAuthorized(request)) return fail("UNAUTHORIZED", "管理令牌无效。", 401);
  try {
    const form = await request.formData(); const file = form.get("file");
    if (!(file instanceof File)) return fail("FILE_REQUIRED", "请选择 SQLite 文件。");
    if (file.size > 2 * 1024 * 1024 * 1024) return fail("FILE_TOO_LARGE", "ECDICT 文件不能超过 2GB。");
    return ok(await installUploadedEcdict(Buffer.from(await file.arrayBuffer())));
  } catch (error) { return internalError(error, error instanceof Error ? error.message : "上传 ECDICT 失败。"); }
}
export async function DELETE(request: NextRequest) {
  if (!isAdminAuthorized(request)) return fail("UNAUTHORIZED", "管理令牌无效。", 401);
  try { return ok(await removeEcdict()); } catch (error) { return internalError(error, "移除 ECDICT 失败。"); }
}
