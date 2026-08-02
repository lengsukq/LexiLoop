import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { startMatchingSession } from "@/modules/matching/service";
import { z } from "zod";

const schema = z.object({
  pairCount: z.number().int().min(4).max(8).default(6),
  durationSeconds: z.number().int().min(30).max(180).default(60),
});

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json().catch(() => ({})));
    return ok(await startMatchingSession(input));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "配对游戏参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "NOT_ENOUGH_MATCHING_WORDS") {
      return fail("NOT_ENOUGH_MATCHING_WORDS", "至少需要 4 个带释义且不重复的可学习词条。", 409);
    }
    return internalError(error, "创建词汇配对失败。");
  }
}
