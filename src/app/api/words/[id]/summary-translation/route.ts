import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { queueAiTask } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function POST(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    // Translation tasks are intentionally coalesced per word. The worker fills
    // the requested header translation and any still-missing example translations.
    return ok({ jobId: await queueAiTask(id, "EXAMPLE_TRANSLATIONS"), queued: true });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "创建释义翻译任务失败。" });
  }
}
