import { NextRequest } from "next/server";
import { authRequired, handleRouteError } from "@/lib/api";
import { isSyncRequestAuthorized } from "@/lib/security";
import { okMaybeGzip, readJsonRequestMaybeGzip } from "@/modules/sync/http-codec";
import { exportSyncPullPage } from "@/modules/sync/pull-exporter";
import { ensureServerSyncState } from "@/modules/sync/server-state";
import { pullRequestSchema } from "@/modules/sync/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  if (!isSyncRequestAuthorized(request)) return authRequired();

  try {
    const body = await readJsonRequestMaybeGzip(request);
    const input = pullRequestSchema.parse(body);
    const state = await ensureServerSyncState();
    const page = await exportSyncPullPage({
      request: input,
      datasetEpoch: state.datasetEpoch,
    });
    return okMaybeGzip(request, page);
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "云端同步拉取失败。", validationMessage: "拉取参数无效。" });
  }
}
