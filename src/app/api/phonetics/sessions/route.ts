import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { PHONETIC_ACCENTS, startPhoneticGame } from "@/modules/phonetics/service";
import { z } from "zod";

const schema = z.object({ accent: z.enum(PHONETIC_ACCENTS) });

export const dynamic = "force-dynamic";

export async function POST(request: NextRequest) {
  try {
    const { accent } = schema.parse(await request.json());
    return ok(startPhoneticGame(accent));
  } catch (error) {
    if (error instanceof z.ZodError) {
      return fail("VALIDATION_ERROR", "音标训练口音无效。", 400, error.issues);
    }
    if (error instanceof Error && error.message === "NOT_ENOUGH_PHONETIC_WORDS") {
      return fail("NOT_ENOUGH_PHONETIC_WORDS", "至少需要 4 个带有对应音标的可学习单词。请先在初始化页补齐音标。", 409);
    }
    return internalError(error, "创建音标训练失败。");
  }
}
