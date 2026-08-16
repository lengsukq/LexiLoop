import { handleRouteError, ok, requireRouteId } from "@/lib/api";
import { queueAiTask } from "@/modules/initialization/service";
import { translateExample } from "@/modules/translations/service";
import { z } from "zod";

export const dynamic = "force-dynamic";

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  try {
    const id = requireRouteId((await params).id, "WORD_ID_INVALID", "词条 ID 无效。");
    const body = await request.json().catch(() => null);
    if (body && typeof body === "object" && "index" in body) {
      const { index } = z.object({ index: z.number().int().nonnegative() }).strict().parse(body);
      return ok(await translateExample(id, index));
    }
    return ok({ jobId: await queueAiTask(id, "EXAMPLE_TRANSLATIONS"), queued: true });
  } catch (error) {
    return handleRouteError(error, { validationMessage: "例句翻译参数无效。", fallbackMessage: "创建例句翻译任务失败。" });
  }
}
