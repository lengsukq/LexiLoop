import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { PHONETIC_ACCENTS, startPhoneticGame } from "@/modules/phonetics/service";
import { z } from "zod";

const schema = z.object({ accent: z.enum(PHONETIC_ACCENTS) });

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const { accent } = schema.parse(await request.json());
    return ok(await startPhoneticGame(accent));
  } catch (error) {
    return handleRouteError(error, { validationMessage: "音标训练口音无效。", fallbackMessage: "创建音标训练失败。" });
  }
}
