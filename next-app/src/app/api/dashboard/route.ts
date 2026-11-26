import { ok, internalError } from "@/lib/api";
import { getDashboard } from "@/modules/statistics/service";
export const dynamic = "force-dynamic";
export async function GET() { try { return ok(await getDashboard()); } catch (error) { return internalError(error, "获取首页数据失败。"); } }
