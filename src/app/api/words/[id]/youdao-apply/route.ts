import type { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
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
    const id = Number((await context.params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。", 400);
    const input = schema.parse(await request.json());
    const content = normalizeDictionaryContent(input.content);
    const attempts = input.attempts as ProviderAttempt[];
    const detail = await applyYoudaoContent(id, content, input.mode, attempts, input.newTerm);
    if (!detail) return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    return ok(detail);
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "应用参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    if (error instanceof Error && error.message === "TERM_ALREADY_EXISTS") return fail("TERM_ALREADY_EXISTS", "已存在相同词条，无法修改为该文本。", 409);
    if (error instanceof Error && error.message === "TERM_REQUIRED") return fail("TERM_REQUIRED", "词条文本不能为空。", 400);
    if (error instanceof Error && error.message === "TERM_TOO_LONG") return fail("TERM_TOO_LONG", "词条文本过长。", 400);
    return internalError(error, "应用有道词典内容失败。");
  }
}
