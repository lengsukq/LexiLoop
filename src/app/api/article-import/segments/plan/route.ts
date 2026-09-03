import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { planArticleSegments } from "@/modules/article-import/service";
import { z } from "zod";

const schema = z.object({
  articleText: z.string().min(1).max(60_000),
  segmentsPerBatch: z.number().int().min(1).max(10).default(1),
});

export const runtime = "nodejs";
export const maxDuration = 30;

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    const plan = planArticleSegments(input.articleText, input.segmentsPerBatch);
    const { rawSegments: _raw, ...rest } = plan as unknown as { rawSegments: unknown } & Omit<typeof plan, "rawSegments">;
    void _raw;
    return ok(rest);
  } catch (error) {
    return handleRouteError(error, { validationMessage: "分段参数无效。", fallbackMessage: "生成分段预览失败。" });
  }
}
