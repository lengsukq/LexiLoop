import { fail, internalError, ok } from "@/lib/api";
import { queueAiTask } from "@/modules/initialization/service";
import { translateExample } from "@/modules/translations/service";
import { z } from "zod";

export const dynamic = "force-dynamic";

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。");
    const body = await request.json().catch(() => null);
    if (body && typeof body === "object" && "index" in body) {
      const { index } = z.object({ index: z.number().int().nonnegative() }).strict().parse(body);
      return ok(await translateExample(id, index));
    }
    return ok({ jobId: await queueAiTask(id, "EXAMPLE_TRANSLATIONS"), queued: true });
  } catch (error) {
    if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "例句翻译参数无效。", 400, error.issues);
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    if (error instanceof Error && error.message === "EXAMPLE_NOT_FOUND") return fail("EXAMPLE_NOT_FOUND", "例句不存在。", 404);
    return internalError(error, "创建例句翻译任务失败。");
  }
}
