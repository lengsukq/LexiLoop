import { NextRequest } from "next/server";
import { sqlite } from "@/db/client";
import { authRequired, handleRouteError, ok } from "@/lib/api";
import { isPasswordEnabled, isSyncRequestAuthorized } from "@/lib/security";
import { ensureServerSyncState } from "@/modules/sync/server-state";
import { CLOUD_SYNC_PROTOCOL_VERSION } from "@/modules/sync/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export async function GET(request: NextRequest) {
  if (!isSyncRequestAuthorized(request)) return authRequired();

  try {
    const state = await ensureServerSyncState();
    const countRow = await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count?: number } | undefined;
    const peers = Object.values(state.peerWatermarks).sort((a, b) => b.lastSyncedAt - a.lastSyncedAt);
    return ok({
      protocolVersion: CLOUD_SYNC_PROTOCOL_VERSION,
      passwordProtected: isPasswordEnabled(),
      deviceId: state.deviceId,
      datasetEpoch: state.datasetEpoch,
      wordCount: countRow?.count ?? 0,
      peers,
    });
  } catch (error) {
    return handleRouteError(error, { fallbackMessage: "读取云端同步状态失败。" });
  }
}
