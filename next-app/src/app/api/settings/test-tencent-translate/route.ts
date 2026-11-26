import { NextRequest } from "next/server";
import { errorMessage } from "@/lib/format";
import { fail, internalError, ok } from "@/lib/api";
import { tencentTranslateText, TencentTranslateError } from "@/lib/tencent-translate-client";
import { z } from "zod";

export const dynamic = "force-dynamic";

const testSchema = z.object({
  secretId: z.string().min(1),
  secretKey: z.string().min(1),
  projectId: z.number().int().min(0).default(0),
});

export async function POST(request: NextRequest) {
  try {
    const input = testSchema.parse(await request.json());
    const start = Date.now();
    const result = await tencentTranslateText("hello", "en", "zh", {
      secretId: input.secretId,
      secretKey: input.secretKey,
      projectId: input.projectId,
    });
    return ok({ translation: result, durationMs: Date.now() - start });
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "参数无效", 400, error.issues);
    if (error instanceof TencentTranslateError) {
      return fail(error.code, error.message, error.status);
    }
    const timeout = error instanceof DOMException && error.name === "TimeoutError";
    if (timeout) return fail("TIMEOUT", "连接超时（8秒）", 504);
    return internalError(error, errorMessage(error, "连接失败"));
  }
}
