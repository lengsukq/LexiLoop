import { NextRequest } from "next/server";
import { fail, internalError, ok } from "@/lib/api";
import { getReviewPreview } from "@/modules/reviews/service";
import { z } from "zod";
const schema = z.object({ wordId: z.number().int().positive() });
export async function POST(request: NextRequest) { try { return ok(await getReviewPreview(schema.parse(await request.json()).wordId)); } catch (error) { if (error instanceof z.ZodError) return fail("VALIDATION_ERROR", "词条 ID 无效。", 400, error.issues); return internalError(error, "获取复习间隔失败。"); } }
