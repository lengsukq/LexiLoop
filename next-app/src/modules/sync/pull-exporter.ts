import { sqlite } from "@/db/client";
import { utf8ByteLength } from "@/lib/iso-crypto";
import {
  CLOUD_SYNC_DELTA_FORMAT,
  CLOUD_SYNC_DELTA_VERSION,
  DELTA_LOOKBACK_MS,
  DELTA_TABLE_ORDER,
  MAX_PULL_PAGE_BYTES,
  REPLACE_TABLE_ORDER,
  SQL_BATCH_SIZE,
  SYNC_EXCLUDED_SETTING_KEYS,
  type PullRequest,
  type SyncPullCursor,
  type SyncRow,
} from "./types";

const CONTENT_FETCH_LIMIT = 60;
const DEFAULT_FETCH_LIMIT = 200;

export interface PullPageResult {
  format: string;
  version: number;
  mode: "delta" | "replace";
  isIncremental: boolean;
  serverNow: number;
  snapshotAt: number;
  datasetEpoch: string;
  since: number | null;
  hasMore: boolean;
  nextCursor: SyncPullCursor | null;
  word_refs: SyncRow[];
  tables: Record<string, SyncRow[]>;
  rowCount: number;
}

function asInt(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function estimateRowBytes(row: SyncRow): number {
  return utf8ByteLength(JSON.stringify(row)) + 2;
}

function sessionChangedWhere(alias: string): string {
  return `(
    ${alias}.started_at >= ?
    OR ${alias}.completed_at >= ?
    OR ${alias}.created_at >= ?
    OR EXISTS (
      SELECT 1 FROM study_session_items ssi
      WHERE ssi.study_session_id = ${alias}.id
        AND (ssi.answered_at >= ? OR ssi.created_at >= ?)
    )
    OR EXISTS (
      SELECT 1 FROM review_logs rl
      WHERE rl.study_session_id = ${alias}.id
        AND (rl.created_at >= ? OR rl.reviewed_at >= ?)
    )
  )`;
}

function sessionChangedParams(cutoff: number): number[] {
  return [cutoff, cutoff, cutoff, cutoff, cutoff, cutoff, cutoff];
}

async function fetchTableSlice(
  table: string,
  cutoff: number | null,
  cursor: SyncPullCursor,
  limit: number,
): Promise<SyncRow[]> {
  const isDelta = cutoff !== null;

  switch (table) {
    case "words": {
      const lastId = cursor.lastId ?? 0;
      if (!isDelta) {
        return await sqlite
          .prepare("SELECT * FROM words WHERE id > ? ORDER BY id ASC LIMIT ?")
          .all(lastId, limit) as SyncRow[];
      }
      return await sqlite
        .prepare("SELECT * FROM words WHERE id > ? AND updated_at >= ? ORDER BY id ASC LIMIT ?")
        .all(lastId, cutoff, limit) as SyncRow[];
    }
    case "word_contents": {
      const lastId = cursor.lastId ?? 0;
      if (!isDelta) {
        return await sqlite
          .prepare("SELECT * FROM word_contents WHERE word_id > ? ORDER BY word_id ASC LIMIT ?")
          .all(lastId, limit) as SyncRow[];
      }
      return await sqlite
        .prepare("SELECT * FROM word_contents WHERE word_id > ? AND updated_at >= ? ORDER BY word_id ASC LIMIT ?")
        .all(lastId, cutoff, limit) as SyncRow[];
    }
    case "study_sessions": {
      const lastId = cursor.lastId ?? 0;
      if (!isDelta) {
        return await sqlite
          .prepare("SELECT * FROM study_sessions WHERE id > ? ORDER BY id ASC LIMIT ?")
          .all(lastId, limit) as SyncRow[];
      }
      return await sqlite
        .prepare(`SELECT * FROM study_sessions s WHERE s.id > ? AND ${sessionChangedWhere("s")} ORDER BY s.id ASC LIMIT ?`)
        .all(lastId, ...sessionChangedParams(cutoff), limit) as SyncRow[];
    }
    case "study_session_items": {
      const lastId = cursor.lastId ?? 0;
      if (!isDelta) {
        return await sqlite
          .prepare("SELECT * FROM study_session_items WHERE id > ? ORDER BY id ASC LIMIT ?")
          .all(lastId, limit) as SyncRow[];
      }
      return await sqlite
        .prepare(
          `SELECT i.* FROM study_session_items i
           JOIN study_sessions s ON s.id = i.study_session_id
           WHERE i.id > ? AND ${sessionChangedWhere("s")}
           ORDER BY i.id ASC LIMIT ?`,
        )
        .all(lastId, ...sessionChangedParams(cutoff), limit) as SyncRow[];
    }
    case "review_cards": {
      const lastId = cursor.lastId ?? 0;
      return await sqlite
        .prepare("SELECT * FROM review_cards WHERE word_id > ? ORDER BY word_id ASC LIMIT ?")
        .all(lastId, limit) as SyncRow[];
    }
    case "review_logs": {
      const lastId = cursor.lastId ?? 0;
      if (!isDelta) {
        return await sqlite
          .prepare("SELECT * FROM review_logs WHERE id > ? ORDER BY id ASC LIMIT ?")
          .all(lastId, limit) as SyncRow[];
      }
      return await sqlite
        .prepare("SELECT * FROM review_logs WHERE id > ? AND (created_at >= ? OR reviewed_at >= ?) ORDER BY id ASC LIMIT ?")
        .all(lastId, cutoff, cutoff, limit) as SyncRow[];
    }
    case "wrong_word_states": {
      const lastId = cursor.lastId ?? 0;
      return await sqlite
        .prepare("SELECT * FROM wrong_word_states WHERE word_id > ? ORDER BY word_id ASC LIMIT ?")
        .all(lastId, limit) as SyncRow[];
    }
    case "settings": {
      const lastKey = cursor.lastKey;
      const whereParts: string[] = [];
      const params: unknown[] = [];
      if (lastKey !== undefined) {
        whereParts.push("key > ?");
        params.push(lastKey);
      }
      if (isDelta) {
        whereParts.push("updated_at >= ?");
        params.push(cutoff);
      }
      const whereSql = whereParts.length > 0 ? `WHERE ${whereParts.join(" AND ")}` : "";
      params.push(limit);
      return await sqlite
        .prepare(`SELECT * FROM settings ${whereSql} ORDER BY key ASC LIMIT ?`)
        .all(...params) as SyncRow[];
    }
    case "word_packs": {
      const lastKey = cursor.lastKey;
      const whereParts: string[] = [];
      const params: unknown[] = [];
      if (lastKey !== undefined) {
        whereParts.push("p.id > ?");
        params.push(lastKey);
      }
      if (isDelta) {
        whereParts.push(
          `(p.updated_at >= ? OR EXISTS (
            SELECT 1 FROM word_pack_items pi
            JOIN words w ON w.id = pi.word_id
            WHERE pi.pack_id = p.id AND w.updated_at >= ?
          ))`,
        );
        params.push(cutoff, cutoff);
      }
      const whereSql = whereParts.length > 0 ? `WHERE ${whereParts.join(" AND ")}` : "";
      params.push(limit);
      return await sqlite
        .prepare(`SELECT p.* FROM word_packs p ${whereSql} ORDER BY p.id ASC LIMIT ?`)
        .all(...params) as SyncRow[];
    }
    case "word_pack_items": {
      const whereParts: string[] = [];
      const params: unknown[] = [];
      if (cursor.lastPackId !== undefined && cursor.lastWordId !== undefined) {
        whereParts.push("(pi.pack_id > ? OR (pi.pack_id = ? AND pi.word_id > ?))");
        params.push(cursor.lastPackId, cursor.lastPackId, cursor.lastWordId);
      }
      if (isDelta) {
        whereParts.push(
          `(EXISTS (SELECT 1 FROM word_packs p WHERE p.id = pi.pack_id AND p.updated_at >= ?)
            OR EXISTS (SELECT 1 FROM words w WHERE w.id = pi.word_id AND w.updated_at >= ?))`,
        );
        params.push(cutoff, cutoff);
      }
      const whereSql = whereParts.length > 0 ? `WHERE ${whereParts.join(" AND ")}` : "";
      params.push(limit);
      return await sqlite
        .prepare(`SELECT pi.* FROM word_pack_items pi ${whereSql} ORDER BY pi.pack_id ASC, pi.word_id ASC LIMIT ?`)
        .all(...params) as SyncRow[];
    }
    default:
      return [];
  }
}

function advanceCursor(table: string, tableIndex: number, row: SyncRow): SyncPullCursor {
  switch (table) {
    case "word_contents":
    case "review_cards":
    case "wrong_word_states":
      return { tableIndex, lastId: asInt(row.word_id) ?? 0 };
    case "settings":
      return { tableIndex, lastKey: asString(row.key) };
    case "word_packs":
      return { tableIndex, lastKey: asString(row.id) };
    case "word_pack_items":
      return {
        tableIndex,
        lastPackId: asString(row.pack_id),
        lastWordId: asInt(row.word_id) ?? 0,
      };
    default:
      return { tableIndex, lastId: asInt(row.id) ?? 0 };
  }
}

async function loadPageWordRefs(tables: Record<string, SyncRow[]>): Promise<SyncRow[]> {
  const present = new Set<number>();
  for (const row of tables.words ?? []) {
    const id = asInt(row.id);
    if (id !== null) present.add(id);
  }
  const needed = new Set<number>();
  for (const table of ["word_contents", "study_session_items", "review_logs", "word_pack_items"]) {
    for (const row of tables[table] ?? []) {
      const wid = asInt(row.word_id);
      if (wid !== null && !present.has(wid)) needed.add(wid);
    }
  }
  if (needed.size === 0) return [];

  const ids = [...needed];
  const refs: SyncRow[] = [];
  for (let start = 0; start < ids.length; start += SQL_BATCH_SIZE) {
    const chunk = ids.slice(start, start + SQL_BATCH_SIZE);
    const marks = chunk.map(() => "?").join(", ");
    const rows = await sqlite
      .prepare(`SELECT id, normalized_term, source_language, target_language FROM words WHERE id IN (${marks})`)
      .all(...chunk) as SyncRow[];
    refs.push(...rows);
  }
  return refs;
}

/**
 * Exports one keyset-paginated slice of server changes (delta or full replace),
 * strictly bounded by `maxPageBytes` so every response remains well under Vercel's 4.5 MB limit.
 */
export async function exportSyncPullPage(params: {
  request: PullRequest;
  datasetEpoch: string;
  now?: number;
}): Promise<PullPageResult> {
  const now = params.now ?? Date.now();
  const mode = params.request.mode;
  const tableOrder = mode === "replace" ? REPLACE_TABLE_ORDER : DELTA_TABLE_ORDER;
  const snapshotAt = params.request.snapshotAt ?? now;
  const since = mode === "replace" ? null : (params.request.since ?? null);
  const isIncremental = since !== null && since > 0;
  const cutoff = isIncremental ? Math.max(0, since - DELTA_LOOKBACK_MS) : null;
  const budgetBytes = Math.min(params.request.maxPageBytes ?? MAX_PULL_PAGE_BYTES, MAX_PULL_PAGE_BYTES);

  const tables: Record<string, SyncRow[]> = {};
  for (const name of tableOrder) tables[name] = [];

  let cursor: SyncPullCursor = params.request.cursor ?? { tableIndex: 0 };
  let usedBytes = 0;
  let totalRows = 0;
  let hasMore = false;

  while (cursor.tableIndex < tableOrder.length) {
    const table = tableOrder[cursor.tableIndex]!;
    const fetchLimit = table === "word_contents" ? CONTENT_FETCH_LIMIT : DEFAULT_FETCH_LIMIT;
    let tableExhausted = false;

    while (!tableExhausted) {
      const slice = await fetchTableSlice(table, cutoff, cursor, fetchLimit);
      if (slice.length === 0) {
        tableExhausted = true;
        break;
      }

      for (const row of slice) {
        if (table === "settings" && SYNC_EXCLUDED_SETTING_KEYS.has(asString(row.key))) {
          cursor = advanceCursor(table, cursor.tableIndex, row);
          continue;
        }
        const rowBytes = estimateRowBytes(row);
        if (totalRows > 0 && usedBytes + rowBytes > budgetBytes) {
          hasMore = true;
          break;
        }
        tables[table]!.push(row);
        usedBytes += rowBytes;
        totalRows += 1;
        cursor = advanceCursor(table, cursor.tableIndex, row);
      }

      if (hasMore) break;
      if (slice.length < fetchLimit) tableExhausted = true;
    }

    if (hasMore) break;
    cursor = { tableIndex: cursor.tableIndex + 1 };
  }

  const wordRefs = mode === "delta" ? await loadPageWordRefs(tables) : [];
  return {
    format: CLOUD_SYNC_DELTA_FORMAT,
    version: CLOUD_SYNC_DELTA_VERSION,
    mode,
    isIncremental,
    serverNow: snapshotAt,
    snapshotAt,
    datasetEpoch: params.datasetEpoch,
    since,
    hasMore,
    nextCursor: hasMore ? cursor : null,
    word_refs: wordRefs,
    tables,
    rowCount: totalRows,
  };
}
