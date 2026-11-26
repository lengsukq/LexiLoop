import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { mergeArticlePreviews } from "@/modules/article-import/service";
import { z } from "zod";

const schema = z.object({
  tokens: z.array(z.string().uuid()).min(1).max(20),
});

export const runtime = "nodejs";
export const maxDuration = 30;

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    const preview = await mergeArticlePreviews(input.tokens);
    return ok(preview);
  } catch (error) {
    return handleRouteError(error, { validationMessage: "合并参数无效。", fallbackMessage: "合并段落预览失败。" });
  }
}
