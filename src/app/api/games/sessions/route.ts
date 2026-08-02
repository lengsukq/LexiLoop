import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { GAME_MODES, startGameSession } from "@/modules/games/service";
import { z } from "zod";

const schema = z.object({ mode: z.enum(GAME_MODES) });

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const { mode } = schema.parse(await request.json());
    return ok(await startGameSession(mode));
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "小游戏模式无效。", 400, error.issues);
    if (error instanceof Error && error.message === "NOT_ENOUGH_GAME_WORDS") {
      return fail("NOT_ENOUGH_GAME_WORDS", "至少需要 4 个带有效释义的可学习词条。", 409);
    }
    return internalError(error, "创建小游戏失败。");
  }
}
