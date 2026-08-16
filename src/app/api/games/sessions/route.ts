import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { GAME_MODES, startGameSession } from "@/modules/games/service";
import { z } from "zod";

const schema = z.object({ mode: z.enum(GAME_MODES) });

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const { mode } = schema.parse(await request.json());
    return ok(await startGameSession(mode));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "小游戏模式无效。", fallbackMessage: "创建小游戏失败。" });
  }
}
