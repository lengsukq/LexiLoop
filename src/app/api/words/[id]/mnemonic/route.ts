import { fail, internalError, ok } from "@/lib/api";
import { queueAiTask } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = Number((await params).id);
    if (!Number.isInteger(id) || id <= 0) return fail("WORD_ID_INVALID", "词条 ID 无效。");
    return ok({ jobId: await queueAiTask(id, "MNEMONIC"), queued: true });
  } catch (error) {
    if (error instanceof Error && error.message === "WORD_NOT_FOUND") return fail("WORD_NOT_FOUND", "词条不存在。", 404);
    return internalError(error, "创建助记任务失败。");
  }
}
