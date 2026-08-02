import { fail, internalError, ok } from "@/lib/api";
import { queueAiTask } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。", 400);
    // Translation tasks are intentionally coalesced per word. The worker fills
    // the requested header translation and any still-missing example translations.
    return ok({ jobId: await queueAiTask(id, "EXAMPLE_TRANSLATIONS"), queued: true });
  } catch (error) {
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    return internalError(error, "创建释义翻译任务失败。");
  }
}
