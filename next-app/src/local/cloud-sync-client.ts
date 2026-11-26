import { SYNC_PASSWORD_HEADER } from "@/lib/sync-constants";
import { ensureBrowserDbReady } from "@/local/browser-db-client";
import { invalidateSettingsCache } from "@/modules/settings/service";
import { exportSyncPullPage, type PullPageResult } from "@/modules/sync/pull-exporter";
import { applySyncPushBatch } from "@/modules/sync/push-merger";
import { ensureServerSyncState, recordServerPeerSync } from "@/modules/sync/server-state";
import {
  CLOUD_SYNC_DELTA_FORMAT,
  CLOUD_SYNC_DELTA_VERSION,
  CLOUD_SYNC_PROTOCOL_VERSION,
  type PushRequest,
  type SyncPullCursor,
  type SyncRow,
} from "@/modules/sync/types";

export interface LocalCloudSyncOptions {
  serverUrl: string;
  password?: string;
}

export interface LocalCloudSyncResult {
  pulled: {
    pages: number;
    addedWords: number;
    updatedWords: number;
    addedLogs: number;
  };
  pushed: {
    pages: number;
    addedWords: number;
    updatedWords: number;
    addedLogs: number;
  };
  serverWordCount: number;
  localWordCount: number;
}

interface HandshakeResponse {
  service: string;
  protocolVersion: number;
  deviceId: string;
  datasetEpoch: string;
  serverNow: number;
  wordCount: number;
  pushSince: number | null;
  pullFullRequired: boolean;
}

interface RemoteApplyResult {
  summary: {
    addedWords: number;
    updatedWords: number;
    addedLogs: number;
    rebuiltWords: number;
    wordCount: number;
  };
  datasetEpoch: string;
  serverNow: number;
}

function normalizeServerOrigin(raw: string): string {
  const trimmed = raw.trim().replace(/\/+$/, "");
  if (!trimmed) return typeof window !== "undefined" ? window.location.origin : "";
  return trimmed;
}

async function encodeBodyMaybeGzip(payload: unknown): Promise<{
  body: BodyInit;
  headers: Record<string, string>;
}> {
  const json = JSON.stringify(payload);
  if (typeof CompressionStream !== "undefined") {
    try {
      const stream = new Blob([json]).stream().pipeThrough(new CompressionStream("gzip"));
      const buffer = await new Response(stream).arrayBuffer();
      return {
        body: new Uint8Array(buffer),
        headers: {
          "content-type": "application/json",
          "content-encoding": "gzip",
          accept: "application/json",
        },
      };
    } catch {
      // Fall back to plain UTF-8 JSON if browser CompressionStream fails.
    }
  }
  return {
    body: json,
    headers: { "content-type": "application/json", accept: "application/json" },
  };
}

async function postSyncEndpoint<T>(
  serverOrigin: string,
  path: string,
  payload: unknown,
  password?: string,
): Promise<T> {
  const encoded = await encodeBodyMaybeGzip(payload);
  const headers: Record<string, string> = { ...encoded.headers };
  if (password && password.trim()) {
    headers[SYNC_PASSWORD_HEADER] = password.trim();
  }

  const response = await fetch(`${serverOrigin}${path}`, {
    method: "POST",
    headers,
    body: encoded.body,
    cache: "no-store",
  });
  const parsed = await response.json().catch(() => null) as {
    success?: boolean;
    data?: T;
    error?: { message?: string };
  } | null;

  if (!response.ok || !parsed?.success) {
    throw new Error(parsed?.error?.message ?? `云同步请求失败（HTTP ${response.status}）`);
  }
  return parsed.data as T;
}

function trackPulledRefs(
  tables: Record<string, SyncRow[]>,
  wordRefsById: Map<number, SyncRow>,
  sessionRefsById: Map<number, SyncRow>,
  itemRefsById: Map<number, SyncRow>,
): void {
  for (const row of tables.words ?? []) {
    const id = Number(row.id);
    if (Number.isInteger(id)) {
      wordRefsById.set(id, {
        id,
        normalized_term: row.normalized_term,
        source_language: row.source_language,
        target_language: row.target_language,
      });
    }
  }
  for (const row of tables.study_sessions ?? []) {
    const id = Number(row.id);
    if (Number.isInteger(id)) {
      sessionRefsById.set(id, {
        id,
        session_type: row.session_type,
        source_type: row.source_type,
        started_at: row.started_at,
      });
    }
  }
  for (const row of tables.study_session_items ?? []) {
    const id = Number(row.id);
    if (Number.isInteger(id)) {
      itemRefsById.set(id, {
        id,
        study_session_id: row.study_session_id,
        position: row.position,
      });
    }
  }
}

function collectCrossPageRefs(
  tables: Record<string, SyncRow[]>,
  wordRefsById: Map<number, SyncRow>,
  sessionRefsById: Map<number, SyncRow>,
  itemRefsById: Map<number, SyncRow>,
) {
  const presentWords = new Set((tables.words ?? []).map((r) => Number(r.id)));
  const presentSessions = new Set((tables.study_sessions ?? []).map((r) => Number(r.id)));
  const presentItems = new Set((tables.study_session_items ?? []).map((r) => Number(r.id)));

  const extraWordRefs = new Map<number, SyncRow>();
  const extraSessionRefs = new Map<number, SyncRow>();
  const extraItemRefs = new Map<number, SyncRow>();

  for (const row of tables.review_logs ?? []) {
    const wid = Number(row.word_id);
    if (!presentWords.has(wid) && wordRefsById.has(wid)) extraWordRefs.set(wid, wordRefsById.get(wid)!);
    const sid = Number(row.study_session_id);
    if (!presentSessions.has(sid) && sessionRefsById.has(sid)) extraSessionRefs.set(sid, sessionRefsById.get(sid)!);
    const iid = Number(row.study_session_item_id);
    if (!presentItems.has(iid) && itemRefsById.has(iid)) extraItemRefs.set(iid, itemRefsById.get(iid)!);
  }
  for (const row of tables.study_session_items ?? []) {
    const sid = Number(row.study_session_id);
    if (!presentSessions.has(sid) && sessionRefsById.has(sid)) extraSessionRefs.set(sid, sessionRefsById.get(sid)!);
  }

  return {
    word_refs: [...extraWordRefs.values()],
    session_refs: [...extraSessionRefs.values()],
    item_refs: [...extraItemRefs.values()],
  };
}

/**
 * Runs a full bidirectional pull + push incremental delta sync between Browser PGlite
 * and a remote/local-origin Next.js LexiLoop server (`/api/sync/*`).
 */
export async function syncLocalWithCloud(options: LocalCloudSyncOptions): Promise<LocalCloudSyncResult> {
  await ensureBrowserDbReady();
  const origin = normalizeServerOrigin(options.serverUrl);
  const localState = await ensureServerSyncState();
  const previousPeer = Object.values(localState.peerWatermarks)[0];

  const handshake = await postSyncEndpoint<HandshakeResponse>(
    origin,
    "/api/sync/handshake",
    {
      protocolVersion: CLOUD_SYNC_PROTOCOL_VERSION,
      deviceId: localState.deviceId,
      deviceName: "浏览器本地模式",
      datasetEpoch: localState.datasetEpoch,
      knownServerEpoch: previousPeer?.peerDatasetEpoch ?? "",
    },
    options.password,
  );

  // 1. Pull server delta (or full delta snapshot on epoch mismatch) into Browser PGlite.
  const pullSince = handshake.pullFullRequired ? null : (previousPeer?.peerCursorMs ?? null);
  let pullCursor: SyncPullCursor | null = null;
  let pullPages = 0;
  let pulledAddedWords = 0;
  let pulledUpdatedWords = 0;
  let pulledAddedLogs = 0;
  const pullWordRefs = new Map<number, SyncRow>();
  const pullSessionRefs = new Map<number, SyncRow>();
  const pullItemRefs = new Map<number, SyncRow>();

  for (;;) {
    const page: PullPageResult = await postSyncEndpoint<PullPageResult>(
      origin,
      "/api/sync/pull",
      {
        mode: "delta",
        since: pullSince,
        snapshotAt: handshake.serverNow,
        cursor: pullCursor,
      },
      options.password,
    );
    pullPages += 1;

    for (const ref of page.word_refs ?? []) {
      const id = Number(ref.id);
      if (Number.isInteger(id)) pullWordRefs.set(id, ref);
    }
    const crossRefs = collectCrossPageRefs(page.tables, pullWordRefs, pullSessionRefs, pullItemRefs);
    const mergedWordRefs = new Map<number, SyncRow>();
    for (const ref of [...(page.word_refs ?? []), ...crossRefs.word_refs]) {
      mergedWordRefs.set(Number(ref.id), ref);
    }

    const pushPayload: PushRequest = {
      format: CLOUD_SYNC_DELTA_FORMAT,
      version: CLOUD_SYNC_DELTA_VERSION,
      clientDeviceId: handshake.deviceId,
      clientDeviceName: "云端服务器",
      clientDatasetEpoch: page.datasetEpoch,
      clientServerNow: page.serverNow,
      pulledServerNow: Date.now(),
      commitWatermark: !page.hasMore,
      word_refs: [...mergedWordRefs.values()],
      session_refs: crossRefs.session_refs,
      item_refs: crossRefs.item_refs,
      words: page.tables.words ?? [],
      word_contents: page.tables.word_contents ?? [],
      study_sessions: page.tables.study_sessions ?? [],
      study_session_items: page.tables.study_session_items ?? [],
      review_logs: page.tables.review_logs ?? [],
      settings: page.tables.settings ?? [],
      word_packs: page.tables.word_packs ?? [],
      word_pack_items: page.tables.word_pack_items ?? [],
    };

    const applied = await applySyncPushBatch(pushPayload);
    pulledAddedWords += applied.summary.addedWords;
    pulledUpdatedWords += applied.summary.updatedWords;
    pulledAddedLogs += applied.summary.addedLogs;
    trackPulledRefs(page.tables, pullWordRefs, pullSessionRefs, pullItemRefs);

    if (!page.hasMore || !page.nextCursor) break;
    pullCursor = page.nextCursor;
  }

  // Record pulled watermark explicitly even when server had 0 changes.
  await recordServerPeerSync({
    peerDeviceId: handshake.deviceId,
    peerDeviceName: "云端服务器",
    peerDatasetEpoch: handshake.datasetEpoch,
    peerCursorMs: handshake.serverNow,
    localCursorMs: Date.now(),
    hasChanges: pulledAddedWords > 0 || pulledUpdatedWords > 0 || pulledAddedLogs > 0,
  });

  // 2. Push local Browser PGlite delta back to the cloud server.
  const latestLocalState = await ensureServerSyncState();
  const pushSnapshotAt = Date.now();
  let localCursor: SyncPullCursor | null = null;
  let pushPages = 0;
  let pushedAddedWords = 0;
  let pushedUpdatedWords = 0;
  let pushedAddedLogs = 0;
  let serverWordCount = handshake.wordCount;
  const pushWordRefs = new Map<number, SyncRow>();
  const pushSessionRefs = new Map<number, SyncRow>();
  const pushItemRefs = new Map<number, SyncRow>();

  for (;;) {
    const localPage = await exportSyncPullPage({
      request: {
        mode: "delta",
        since: handshake.pushSince,
        snapshotAt: pushSnapshotAt,
        cursor: localCursor,
      },
      datasetEpoch: latestLocalState.datasetEpoch,
      now: pushSnapshotAt,
    });
    pushPages += 1;

    for (const ref of localPage.word_refs) {
      pushWordRefs.set(Number(ref.id), ref);
    }
    const crossRefs = collectCrossPageRefs(localPage.tables, pushWordRefs, pushSessionRefs, pushItemRefs);
    const mergedWordRefs = new Map<number, SyncRow>();
    for (const ref of [...localPage.word_refs, ...crossRefs.word_refs]) {
      mergedWordRefs.set(Number(ref.id), ref);
    }

    const remoteRes = await postSyncEndpoint<RemoteApplyResult>(
      origin,
      "/api/sync/push",
      {
        format: CLOUD_SYNC_DELTA_FORMAT,
        version: CLOUD_SYNC_DELTA_VERSION,
        clientDeviceId: latestLocalState.deviceId,
        clientDeviceName: "浏览器本地模式",
        clientDatasetEpoch: latestLocalState.datasetEpoch,
        clientServerNow: pushSnapshotAt,
        pulledServerNow: handshake.serverNow,
        commitWatermark: !localPage.hasMore,
        word_refs: [...mergedWordRefs.values()],
        session_refs: crossRefs.session_refs,
        item_refs: crossRefs.item_refs,
        words: localPage.tables.words ?? [],
        word_contents: localPage.tables.word_contents ?? [],
        study_sessions: localPage.tables.study_sessions ?? [],
        study_session_items: localPage.tables.study_session_items ?? [],
        review_logs: localPage.tables.review_logs ?? [],
        settings: localPage.tables.settings ?? [],
        word_packs: localPage.tables.word_packs ?? [],
        word_pack_items: localPage.tables.word_pack_items ?? [],
      },
      options.password,
    );

    pushedAddedWords += remoteRes.summary.addedWords;
    pushedUpdatedWords += remoteRes.summary.updatedWords;
    pushedAddedLogs += remoteRes.summary.addedLogs;
    serverWordCount = remoteRes.summary.wordCount;
    trackPulledRefs(localPage.tables, pushWordRefs, pushSessionRefs, pushItemRefs);

    if (!localPage.hasMore || !localPage.nextCursor) break;
    localCursor = localPage.nextCursor;
  }

  invalidateSettingsCache();
  const { sqlite } = await import("@/db/client");
  const localCountRow = await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count?: number } | undefined;

  return {
    pulled: {
      pages: pullPages,
      addedWords: pulledAddedWords,
      updatedWords: pulledUpdatedWords,
      addedLogs: pulledAddedLogs,
    },
    pushed: {
      pages: pushPages,
      addedWords: pushedAddedWords,
      updatedWords: pushedUpdatedWords,
      addedLogs: pushedAddedLogs,
    },
    serverWordCount,
    localWordCount: localCountRow?.count ?? 0,
  };
}
