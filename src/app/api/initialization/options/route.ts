import { internalError, ok } from "@/lib/api";
import { getInitializationOptions } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function GET() {
  try {
    return ok(await getInitializationOptions());
  } catch (error) {
    return internalError(error, "获取初始化来源配置失败。");
  }
}
