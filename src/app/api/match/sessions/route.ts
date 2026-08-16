import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
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
    return handleRouteError(error, { validationMessage: "配对游戏参数无效。", fallbackMessage: "创建词汇配对失败。" });
  }
}
