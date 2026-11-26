import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { IMPORT_MODES } from "@/lib/types";
import { runBackgroundTick } from "@/modules/background/tick";
import { commitImport } from "@/modules/imports/service";
import { z } from "zod";
const schema = z.object({ previewToken: z.string().uuid(), mode: z.enum(IMPORT_MODES), resetLearningProgress: z.boolean().default(false) });
export const maxDuration = 60;
export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    const result = await commitImport(input.previewToken, input.mode, input.resetLearningProgress);
    // 导入提交后立即触发一轮后台处理，让新词条的初始化任务马上开始。
    try { await runBackgroundTick({ maxJobs: 3 }); } catch (tickError) { console.error("[BackgroundTick] on-demand tick after import commit failed", tickError); }
    return ok(result);
  }
  catch (error) {
    return handleRouteError(error, { validationMessage: "导入参数无效。", fallbackMessage: "提交导入失败。" });
  }
}
