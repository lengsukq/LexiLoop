import { z } from "zod";

export const CLOUD_SYNC_SERVICE = "lexiloop-cloud-sync";
export const CLOUD_SYNC_PROTOCOL_VERSION = 1;
export const CLOUD_SYNC_DELTA_FORMAT = "lexiloop-json-delta";
export const CLOUD_SYNC_DELTA_VERSION = 1;
export const CLOUD_SYNC_SERVER_SETTINGS_KEY = "cloudSyncServer";
export const CLOUD_SYNC_CLIENT_SETTINGS_KEY = "cloudSync";

/** Raw JSON byte budget per pull page (stays ~300-450 KB after GZip, far below Vercel's 4.5 MB ceiling). */
export const MAX_PULL_PAGE_BYTES = 1_500_000;

/** Safety guard for decompressed push request body (protects against gzip bombs). */
export const MAX_DECOMPRESSED_PUSH_BYTES = 20 * 1024 * 1024;

/** Lookback window (ms) for delta queries to absorb same-ms commit skew; merges are idempotent. */
export const DELTA_LOOKBACK_MS = 1000;

export const MAX_TRACKED_PEERS = 24;
export const SQL_BATCH_SIZE = 200;

/** Parent-first table order for incremental delta sync (aligned with Flutter `incrementalSyncTableOrder`). */
export const DELTA_TABLE_ORDER = [
  "words",
  "word_contents",
  "study_sessions",
  "study_session_items",
  "review_logs",
  "settings",
  "word_packs",
  "word_pack_items",
] as const;

export type DeltaTableName = (typeof DELTA_TABLE_ORDER)[number];

/** Parent-first table order for full replace snapshot pull (includes derived cards & wrong states). */
export const REPLACE_TABLE_ORDER = [
  "words",
  "word_contents",
  "study_sessions",
  "study_session_items",
  "review_cards",
  "review_logs",
  "wrong_word_states",
  "settings",
  "word_packs",
  "word_pack_items",
] as const;

export type ReplaceTableName = (typeof REPLACE_TABLE_ORDER)[number];

/** Local-only or credential settings keys that must never travel across sync merges. */
export const SYNC_EXCLUDED_SETTING_KEYS: ReadonlySet<string> = new Set([
  "lanSync",
  "webdavBackup",
  CLOUD_SYNC_CLIENT_SETTINGS_KEY,
  CLOUD_SYNC_SERVER_SETTINGS_KEY,
  "llmConfig",
  "merriamWebsterDictionaryKey",
  "merriamWebsterThesaurusKey",
  "tencentTranslateSecretId",
  "tencentTranslateSecretKey",
]);

export type SyncRow = Record<string, unknown>;

export interface SyncPullCursor {
  tableIndex: number;
  lastId?: number;
  lastKey?: string;
  lastPackId?: string;
  lastWordId?: number;
}

export interface SyncPeerWatermark {
  peerDeviceId: string;
  peerDeviceName: string;
  peerDatasetEpoch: string;
  peerCursorMs: number;
  localCursorMs: number;
  lastSyncedAt: number;
}

export interface CloudSyncServerState {
  deviceId: string;
  datasetEpoch: string;
  peerWatermarks: Record<string, SyncPeerWatermark>;
}

export interface SyncMergeSummary {
  addedWords: number;
  updatedWords: number;
  addedLogs: number;
  rebuiltWords: number;
  wordCount: number;
}

const syncRowSchema = z.record(z.string(), z.unknown());

export const handshakeRequestSchema = z.object({
  protocolVersion: z.number().int().min(1).default(CLOUD_SYNC_PROTOCOL_VERSION),
  deviceId: z.string().trim().max(128).default(""),
  deviceName: z.string().trim().max(128).default(""),
  datasetEpoch: z.string().trim().max(128).default(""),
  knownServerEpoch: z.string().trim().max(128).default(""),
});

export const pullCursorSchema = z.object({
  tableIndex: z.number().int().min(0),
  lastId: z.number().int().optional(),
  lastKey: z.string().optional(),
  lastPackId: z.string().optional(),
  lastWordId: z.number().int().optional(),
});

export const pullRequestSchema = z.object({
  mode: z.enum(["delta", "replace"]).default("delta"),
  since: z.number().int().min(0).nullable().optional(),
  snapshotAt: z.number().int().positive().optional(),
  cursor: pullCursorSchema.nullable().optional(),
  maxPageBytes: z.number().int().min(4096).max(MAX_PULL_PAGE_BYTES).optional(),
});

export const pushRequestSchema = z.object({
  format: z.literal(CLOUD_SYNC_DELTA_FORMAT).default(CLOUD_SYNC_DELTA_FORMAT),
  version: z.number().int().min(1).default(CLOUD_SYNC_DELTA_VERSION),
  clientDeviceId: z.string().trim().max(128).default(""),
  clientDeviceName: z.string().trim().max(128).default(""),
  clientDatasetEpoch: z.string().trim().max(128).default(""),
  clientServerNow: z.number().int().min(0).default(0),
  pulledServerNow: z.number().int().min(0).default(0),
  commitWatermark: z.boolean().default(false),
  word_refs: z.array(syncRowSchema).default([]),
  session_refs: z.array(syncRowSchema).default([]),
  item_refs: z.array(syncRowSchema).default([]),
  words: z.array(syncRowSchema).default([]),
  word_contents: z.array(syncRowSchema).default([]),
  study_sessions: z.array(syncRowSchema).default([]),
  study_session_items: z.array(syncRowSchema).default([]),
  review_logs: z.array(syncRowSchema).default([]),
  settings: z.array(syncRowSchema).default([]),
  word_packs: z.array(syncRowSchema).default([]),
  word_pack_items: z.array(syncRowSchema).default([]),
});

export type HandshakeRequest = z.infer<typeof handshakeRequestSchema>;
export type PullRequest = z.infer<typeof pullRequestSchema>;
export type PushRequest = z.infer<typeof pushRequestSchema>;
