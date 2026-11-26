import { internalError, ok } from "@/lib/api";
import { getTodaySuggestion } from "@/modules/suggestions/service";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return ok(await getTodaySuggestion());
  } catch (error) {
    return internalError(error, "生成今日学习建议失败。");
  }
}

export async function POST() {
  try {
    return ok(await getTodaySuggestion({ force: true }));
  } catch (error) {
    return internalError(error, "重新生成今日学习建议失败。");
  }
}
