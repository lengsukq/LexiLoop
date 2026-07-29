import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { retryFailedJobs, retryFailedJobsForWords } from "@/modules/initialization/service";
import { z } from "zod";
const schema = z.union([
  z.object({ jobIds: z.array(z.number().int().positive()).min(1).max(500) }).strict(),
  z.object({ wordIds: z.array(z.number().int().positive()).min(1).max(500) }).strict(),
]);
export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());
    return ok({ retried: "jobIds" in input ? retryFailedJobs(input.jobIds) : retryFailedJobsForWords(input.wordIds) });
  }
  catch (error) { if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "任务 ID 无效。", 400, error.issues); return internalError(error, "重试初始化任务失败。"); }
}
