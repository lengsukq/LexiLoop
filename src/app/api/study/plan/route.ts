import { internalError, ok } from "@/lib/api";
import { getDailyStudyPlan } from "@/modules/study/service";
export const dynamic = "force-dynamic";
export async function GET() { try { return ok(await getDailyStudyPlan()); } catch (error) { return internalError(error, "获取学习计划失败。"); } }
