import { sqlite } from "@/db/client";
import { randomHexToken } from "@/lib/iso-crypto";
import {
  CLOUD_SYNC_SERVER_SETTINGS_KEY,
  MAX_TRACKED_PEERS,
  type CloudSyncServerState,
  type SyncPeerWatermark,
} from "./types";

function generateHexToken(length = 16): string {
  return randomHexToken(length);
}

function asNonNegativeInt(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value) && value > 0) return Math.round(value);
  return 0;
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function parsePeerWatermark(raw: unknown): SyncPeerWatermark | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const record = raw as Record<string, unknown>;
  const peerDeviceId = asTrimmedString(record.peerDeviceId);
  if (!peerDeviceId) return null;
  return {
    peerDeviceId,
    peerDeviceName: asTrimmedString(record.peerDeviceName),
    peerDatasetEpoch: asTrimmedString(record.peerDatasetEpoch),
    peerCursorMs: asNonNegativeInt(record.peerCursorMs),
    localCursorMs: asNonNegativeInt(record.localCursorMs),
    lastSyncedAt: asNonNegativeInt(record.lastSyncedAt),
  };
}

function capWatermarks(input: Record<string, SyncPeerWatermark>): Record<string, SyncPeerWatermark> {
  const entries = Object.values(input);
  if (entries.length <= MAX_TRACKED_PEERS) return input;
  entries.sort((a, b) => b.lastSyncedAt - a.lastSyncedAt);
  const capped: Record<string, SyncPeerWatermark> = {};
  for (const item of entries.slice(0, MAX_TRACKED_PEERS)) {
    capped[item.peerDeviceId] = item;
  }
  return capped;
}

function parseServerState(raw: unknown): CloudSyncServerState | null {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const record = raw as Record<string, unknown>;
  const deviceId = asTrimmedString(record.deviceId);
  const datasetEpoch = asTrimmedString(record.datasetEpoch);
  if (!deviceId || !datasetEpoch) return null;

  const peerWatermarks: Record<string, SyncPeerWatermark> = {};
  if (record.peerWatermarks && typeof record.peerWatermarks === "object" && !Array.isArray(record.peerWatermarks)) {
    for (const value of Object.values(record.peerWatermarks as Record<string, unknown>)) {
      const parsed = parsePeerWatermark(value);
      if (parsed) peerWatermarks[parsed.peerDeviceId] = parsed;
    }
  }
  return { deviceId, datasetEpoch, peerWatermarks: capWatermarks(peerWatermarks) };
}

async function readRawServerState(): Promise<CloudSyncServerState | null> {
  const row = await sqlite
    .prepare("SELECT value_json FROM settings WHERE key = ?")
    .get(CLOUD_SYNC_SERVER_SETTINGS_KEY) as { value_json?: string } | undefined;
  if (!row?.value_json) return null;
  try {
    return parseServerState(JSON.parse(row.value_json));
  } catch {
    return null;
  }
}

async function writeServerState(state: CloudSyncServerState, now = Date.now()): Promise<void> {
  const normalized: CloudSyncServerState = {
    deviceId: state.deviceId,
    datasetEpoch: state.datasetEpoch,
    peerWatermarks: capWatermarks(state.peerWatermarks),
  };
  await sqlite
    .prepare(
      `INSERT INTO settings(key, value_json, updated_at)
       VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value_json = EXCLUDED.value_json, updated_at = EXCLUDED.updated_at`,
    )
    .run(CLOUD_SYNC_SERVER_SETTINGS_KEY, JSON.stringify(normalized), now);
}

/** Loads or initializes the persistent server sync identity (`deviceId` + `datasetEpoch`). */
export async function ensureServerSyncState(now = Date.now()): Promise<CloudSyncServerState> {
  const existing = await readRawServerState();
  if (existing) return existing;
  const created: CloudSyncServerState = {
    deviceId: generateHexToken(16),
    datasetEpoch: generateHexToken(16),
    peerWatermarks: {},
  };
  await writeServerState(created, now);
  return created;
}

/** Rotates server `datasetEpoch` (called after full restore or multi-device merge). */
export async function rotateServerDatasetEpoch(options?: { clearWatermarks?: boolean; now?: number }): Promise<CloudSyncServerState> {
  const now = options?.now ?? Date.now();
  const current = await ensureServerSyncState(now);
  const rotated: CloudSyncServerState = {
    deviceId: current.deviceId,
    datasetEpoch: generateHexToken(16),
    peerWatermarks: options?.clearWatermarks ? {} : current.peerWatermarks,
  };
  await writeServerState(rotated, now);
  return rotated;
}

/** Persists watermark progress for a synced Flutter client, optionally rotating epoch for multi-peer convergence. */
export async function recordServerPeerSync(params: {
  peerDeviceId: string;
  peerDeviceName: string;
  peerDatasetEpoch: string;
  peerCursorMs: number;
  localCursorMs: number;
  hasChanges: boolean;
  now?: number;
}): Promise<CloudSyncServerState> {
  const now = params.now ?? Date.now();
  const current = await ensureServerSyncState(now);
  const hasOtherPeers = Object.keys(current.peerWatermarks).some((id) => id !== params.peerDeviceId);
  const nextEpoch = params.hasChanges && hasOtherPeers ? generateHexToken(16) : current.datasetEpoch;

  const nextWatermarks = { ...current.peerWatermarks };
  if (params.peerDeviceId) {
    const previous = nextWatermarks[params.peerDeviceId];
    nextWatermarks[params.peerDeviceId] = {
      peerDeviceId: params.peerDeviceId,
      peerDeviceName: params.peerDeviceName || previous?.peerDeviceName || params.peerDeviceId,
      peerDatasetEpoch: params.peerDatasetEpoch || previous?.peerDatasetEpoch || "",
      peerCursorMs: params.peerCursorMs > 0 ? params.peerCursorMs : (previous?.peerCursorMs ?? 0),
      localCursorMs: params.localCursorMs > 0 ? params.localCursorMs : (previous?.localCursorMs ?? 0),
      lastSyncedAt: now,
    };
  }

  const nextState: CloudSyncServerState = {
    deviceId: current.deviceId,
    datasetEpoch: nextEpoch,
    peerWatermarks: capWatermarks(nextWatermarks),
  };
  await writeServerState(nextState, now);
  return nextState;
}
