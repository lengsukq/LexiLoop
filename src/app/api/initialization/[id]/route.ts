import { NextRequest } from "next/server";
import { internalError, ok } from "@/lib/api";
import { getJobDetails } from "@/modules/initialization/service";

export const dynamic = "force-dynamic";

export async function GET(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const { id } = await params;
    const jobId = Number(id);
    if (!Number.isFinite(jobId)) return new Response("Invalid job ID", { status: 400 });
    const details = await getJobDetails(jobId);
    if (!details) return new Response("Job not found", { status: 404 });
    return ok(details);
  } catch (error) {
    return internalError(error, "获取任务详情失败。");
  }
}
