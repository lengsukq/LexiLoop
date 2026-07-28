import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { INITIALIZATION_FIELDS, INITIALIZATION_PROVIDER_IDS, PROVIDER_STRATEGIES } from "@/lib/types";
import { queueWordInitialization } from "@/modules/initialization/service";
import { z } from "zod";

const schema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]).default("FILL_MISSING_FIELDS"),
  requestedFields: z.array(z.enum(INITIALIZATION_FIELDS)).min(1).optional(),
  requestedProviders: z.array(z.enum(INITIALIZATION_PROVIDER_IDS)).min(1).optional(),
  providerStrategy: z.enum(PROVIDER_STRATEGIES).optional(),
}).strict();

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await context.params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。");
    const input = schema.parse(await request.json().catch(() => ({})));
    return ok({ jobId: queueWordInitialization(id, input.mode, 100, input), queued: true, mode: input.mode });
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "补全参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    return internalError(error, "创建初始化任务失败。");
  }
}
