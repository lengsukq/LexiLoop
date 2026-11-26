import { NextRequest } from "next/server";
import { authRequired, handleRouteError } from "@/lib/api";
import { isSyncRequestAuthorized } from "@/lib/security";
import { okMaybeGzip, readJsonRequestMaybeGzip } from "@/modules/sync/http-codec";
import { applySyncPushBatch } from "@/modules/sync/push-merger";
import { pushRequestSchema } from "@/modules/sync/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  if (!isSyncRequestAuthorized(request)) return authRequired();

  try {
    const body = await readJsonRequestMaybeGzip(request);
    const input = pushRequestSchema.parse(body);
    const result = await applySyncPushBatch(input);
    return okMaybeGzip(request, result);
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "云端同步写入失败。", validationMessage: "推送载荷格式无效。" });
  }
}
