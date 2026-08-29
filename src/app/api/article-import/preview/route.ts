import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { createArticlePreview } from "@/modules/article-import/service";
import { z } from "zod";

const schema = z.object({
  articleText: z.string().min(1).max(60_000),
  sourceLanguage: z.string().trim().min(1).max(20).optional(),
  targetLanguage: z.string().trim().min(1).max(20).optional(),
  examTargets: z.array(z.enum(["CET4", "CET6", "KY", "IELTS", "TOEFL"])).max(5).optional(),
});

export const runtime = "nodejs";
export const maxDuration = 180;

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    const preview = await createArticlePreview({
      articleText: input.articleText,
      sourceLanguage: input.sourceLanguage,
      targetLanguage: input.targetLanguage,
      examTargets: input.examTargets as ("CET4" | "CET6" | "KY" | "IELTS" | "TOEFL")[] | undefined,
    });
    return ok(preview);
  } catch (error) {
    return handleRouteError(error, { validationMessage: "文章参数无效。", fallbackMessage: "生成文章预览失败。" });
  }
}
