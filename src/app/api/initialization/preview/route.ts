import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { INITIALIZATION_FIELDS, INITIALIZATION_PROVIDER_IDS, PROVIDER_STRATEGIES } from "@/lib/types";
import { previewConfiguredInitialization } from "@/modules/initialization/service";
import { z } from "zod";

const schema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]).default("FILL_MISSING_FIELDS"),
  onlyMissing: z.boolean().default(true),
  wordIds: z.array(z.number().int().positive()).min(1).max(5000).optional(),
  requestedFields: z.array(z.enum(INITIALIZATION_FIELDS)).min(1),
  requestedProviders: z.array(z.enum(INITIALIZATION_PROVIDER_IDS)).min(1),
  providerStrategy: z.enum(PROVIDER_STRATEGIES).default("PARALLEL_MERGE"),
}).strict();

export async function POST(request: NextRequest) {
  try {
    return ok(previewConfiguredInitialization(schema.parse(await request.json())));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "初始化预览参数无效。", 400, error.issues);
    return internalError(error, "计算初始化范围失败。");
  }
}
