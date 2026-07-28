import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { queueBulkInitialization, queueSelectedInitialization } from "@/modules/initialization/service";
import { z } from "zod";

const schema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]).default("FILL_MISSING_FIELDS"),
  onlyWithoutAi: z.boolean().default(true),
  wordIds: z.array(z.number().int().positive()).min(1).max(200).optional(),
}).strict();

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json().catch(() => ({})));
    return ok(input.wordIds
      ? queueSelectedInitialization(input.wordIds, input.mode)
      : queueBulkInitialization(input.mode, input.onlyWithoutAi));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "批量初始化参数无效。", 400, error.issues);
    return internalError(error, "创建批量 AI 初始化任务失败。");
  }
}
