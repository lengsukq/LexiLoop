import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { queueAiTask } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    return ok({ jobId: await queueAiTask(id, "MNEMONIC"), queued: true });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "创建助记任务失败。" });
  }
}
