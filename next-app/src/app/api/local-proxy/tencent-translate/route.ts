import { NextRequest } from "next/server";
import { z } from "zod";
import { fail, internalError, ok } from "@/lib/api";
import { errorMessage } from "@/lib/format";
import { TencentTranslateError, tencentTranslateText } from "@/lib/tencent-translate-client";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const schema = z.object({
  text: z.string().min(1).max(2000),
  source: z.string().min(1).max(32),
  target: z.string().min(1).max(32),
  secretId: z.string().min(1),
  secretKey: z.string().min(1),
  projectId: z.number().int().min(0).default(0),
}).strict();

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    const translation = await tencentTranslateText(input.text, input.source, input.target, {
      secretId: input.secretId,
      secretKey: input.secretKey,
      projectId: input.projectId,
    });
    return ok({ translation });
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "翻译参数无效。", 400, error.issues);
    if (error instanceof TencentTranslateError) return fail(error.code, error.message, error.status);
    const timeout = error instanceof DOMException && error.name === "TimeoutError";
    if (timeout) return fail("TIMEOUT", "腾讯翻译请求超时。", 504);
    return internalError(error, errorMessage(error, "腾讯翻译代理请求失败。"));
  }
}
