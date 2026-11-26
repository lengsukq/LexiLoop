import { NextRequest } from "next/server";
import { sqlite } from "@/db/client";
import { ApiError, authRequired, handleRouteError, ok } from "@/lib/api";
import { isSyncRequestAuthorized } from "@/lib/security";
import { readJsonRequestMaybeGzip } from "@/modules/sync/http-codec";
import { ensureServerSyncState } from "@/modules/sync/server-state";
import {
  CLOUD_SYNC_PROTOCOL_VERSION,
  CLOUD_SYNC_SERVICE,
  handshakeRequestSchema,
} from "@/modules/sync/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function POST(request: NextRequest) {
  if (!isSyncRequestAuthorized(request)) return authRequired();

  try {
    const body = await readJsonRequestMaybeGzip(request);
    const input = handshakeRequestSchema.parse(body);
    if (input.protocolVersion !== CLOUD_SYNC_PROTOCOL_VERSION) {
      throw new ApiError("SYNC_PROTOCOL_MISMATCH");
    }

    const now = Date.now();
    const state = await ensureServerSyncState(now);
    const countRow = await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count?: number } | undefined;
    const peerWm = input.deviceId ? state.peerWatermarks[input.deviceId] : undefined;
    const pushSince =
      peerWm &&
      peerWm.peerDatasetEpoch !== "" &&
      peerWm.peerDatasetEpoch === input.datasetEpoch &&
      peerWm.peerCursorMs > 0
        ? peerWm.peerCursorMs
        : null;

    return ok({
      service: CLOUD_SYNC_SERVICE,
      protocolVersion: CLOUD_SYNC_PROTOCOL_VERSION,
      deviceId: state.deviceId,
      datasetEpoch: state.datasetEpoch,
      serverNow: now,
      wordCount: countRow?.count ?? 0,
      pushSince,
      pullFullRequired: input.knownServerEpoch !== state.datasetEpoch,
    });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "云端同步握手失败。", validationMessage: "握手参数无效。" });
  }
}
