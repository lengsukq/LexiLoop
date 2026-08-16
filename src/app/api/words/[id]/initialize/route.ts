import type { NextRequest } from "next/server";
import { handleRouteError, ok, requireRouteId } from "@/lib/api";
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
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const input = schema.parse(await request.json().catch(() => ({})));
    return ok({ jobId: await queueWordInitialization(id, input.mode, 100, input), queued: true, mode: input.mode });
  } catch (error) {
    return handleRouteError(error, { validationMessage: "补全参数无效。", fallbackMessage: "创建初始化任务失败。" });
  }
}
