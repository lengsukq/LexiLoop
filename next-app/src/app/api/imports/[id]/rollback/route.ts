import type { NextRequest } from "next/server";
import { fail, internalError, ok, requireRouteId } from "@/lib/api";
import { ImportRollbackError, rollbackImportBatch } from "@/modules/imports/service";

export async function POST(_request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "IMPORT_BATCH_ID_INVALID", "导入批次 ID 无效。");
    return ok(await rollbackImportBatch(id));
  } catch (error) {
    if (error instanceof ImportRollbackError) {
      const status = error.code === "IMPORT_BATCH_NOT_FOUND" ? 404 : 409;
      return fail(error.code, error.message, status, error.details);
    }
    return internalError(error, "撤销导入失败。");
  }
}
