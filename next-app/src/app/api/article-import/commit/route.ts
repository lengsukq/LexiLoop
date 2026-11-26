import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { commitArticleImport } from "@/modules/article-import/commit";

export const maxDuration = 120;

export async function POST(request: NextRequest) {
  try {
    return ok(await commitArticleImport(await request.json()));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "提交参数无效。", fallbackMessage: "提交文章导入失败。" });
  }
}
