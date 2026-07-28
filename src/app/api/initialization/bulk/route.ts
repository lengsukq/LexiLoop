import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import {
  INITIALIZATION_FIELDS,
  INITIALIZATION_PROVIDER_IDS,
  PROVIDER_STRATEGIES,
} from "@/lib/types";
import {
  queueBulkInitialization,
  queueConfiguredInitialization,
  queueSelectedInitialization,
} from "@/modules/initialization/service";
import { z } from "zod";

const schema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]).default("FILL_MISSING_FIELDS"),
  onlyWithoutAi: z.boolean().default(true),
  onlyMissing: z.boolean().optional(),
  wordIds: z.array(z.number().int().positive()).min(1).max(5000).optional(),
  requestedFields: z.array(z.enum(INITIALIZATION_FIELDS)).min(1).optional(),
  requestedProviders: z.array(z.enum(INITIALIZATION_PROVIDER_IDS)).min(1).optional(),
  providerStrategy: z.enum(PROVIDER_STRATEGIES).optional(),
}).strict();

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json().catch(() => ({})));
    const configured = Boolean(input.requestedFields?.length || input.requestedProviders?.length || input.providerStrategy || input.onlyMissing !== undefined);
    if (configured) return ok(queueConfiguredInitialization(input));
    return ok(input.wordIds
      ? queueSelectedInitialization(input.wordIds, input.mode)
      : queueBulkInitialization(input.mode, input.onlyWithoutAi));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "批量初始化参数无效。", 400, error.issues);
    return internalError(error, "创建批量初始化任务失败。");
  }
}
