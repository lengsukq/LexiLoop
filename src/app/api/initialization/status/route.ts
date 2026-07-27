import { ok, internalError } from "@/lib/api";
import { getInitializationSummary, getWorkerHeartbeats } from "@/modules/initialization/service";
export const dynamic = "force-dynamic";
export async function GET() { try { return ok({ summary: await getInitializationSummary(), workers: await getWorkerHeartbeats() }); } catch (error) { return internalError(error, "获取初始化状态失败。"); } }
