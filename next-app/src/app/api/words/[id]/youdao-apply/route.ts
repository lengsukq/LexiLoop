import type { NextRequest } from "next/server";
import { fail, handleRouteError, ok, requireRouteId } from "@/lib/api";
import type { ProviderAttempt } from "@/lib/types";
import { normalizeDictionaryContent } from "@/modules/dictionary/content";
import { applyYoudaoContent } from "@/modules/words/youdao-refresh";
import { z } from "zod";

const schema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]),
  content: z.record(z.string(), z.unknown()),
  newTerm: z.string().trim().min(1).max(300).optional(),
  attempts: z.array(z.object({
    providerId: z.string(),
    status: z.string(),
    durationMs: z.number(),
    fieldsReturned: z.array(z.string()).default([]),
    errorCode: z.string().nullable().default(null),
    errorMessage: z.string().nullable().default(null),
    metadata: z.record(z.string(), z.unknown()).nullable().default(null),
  })).default([]),
}).strict();

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await context.params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const input = schema.parse(await request.json());
    const content = normalizeDictionaryContent(input.content);
    const attempts = input.attempts as ProviderAttempt[];
    const detail = await applyYoudaoContent(id, content, input.mode, attempts, input.newTerm);
    if (!detail) return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    return ok(detail);
  } catch (error) {
    return handleRouteError(error, { validationMessage: "应用参数无效。", fallbackMessage: "应用有道词典内容失败。" });
  }
}
