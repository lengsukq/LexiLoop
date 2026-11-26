import { sqlite } from "@/db/client";
import { PG_MIGRATIONS } from "@/db/migrations/pg";
import { ApiError } from "@/lib/api";
import { DAY_MS } from "@/lib/time";
import { invalidateSettingsCache } from "@/modules/settings/service";
import { rotateServerDatasetEpoch } from "@/modules/sync/server-state";
import { CLOUD_SYNC_SERVER_SETTINGS_KEY } from "@/modules/sync/types";

const TABLES = [
  "words", "word_contents", "review_cards", "review_logs", "wrong_word_states",
  "import_batches", "import_rows", "initialization_jobs", "provider_attempts",
  "study_sessions", "study_session_items", "settings", "word_packs", "word_pack_items",
] as const;

type BackupTable = (typeof TABLES)[number];

// Child tables first (FK children before parents) for TRUNCATE/CASCADE-safe clearing.
const RESTORE_ORDER: readonly BackupTable[] = [
  "word_pack_items",
  "word_packs",
  "provider_attempts",
  "initialization_jobs",
  "import_rows",
  "import_batches",
  "wrong_word_states",
  "review_logs",
  "review_cards",
  "study_session_items",
  "study_sessions",
  "word_contents",
  "words",
  "settings",
] as const;

// BIGSERIAL columns whose sequences must be re-synced after explicit id inserts.
const SERIAL_SEQUENCES: ReadonlyArray<{ table: string; column: string }> = [
  { table: "words", column: "id" },
  { table: "study_sessions", column: "id" },
  { table: "study_session_items", column: "id" },
  { table: "review_logs", column: "id" },
  { table: "import_batches", column: "id" },
  { table: "import_rows", column: "id" },
  { table: "initialization_jobs", column: "id" },
  { table: "provider_attempts", column: "id" },
];

const BOOLEAN_INT_COLUMNS: Readonly<Record<string, ReadonlySet<string>>> = {
  words: new Set(["is_suspended", "is_personal"]),
  review_logs: new Set(["is_correct"]),
  wrong_word_states: new Set(["active"]),
  import_batches: new Set(["reset_learning_progress"]),
  word_packs: new Set(["include_in_daily_study"]),
};

const MAX_BACKUP_BYTES = 100 * 1024 * 1024;
const MASTERY_WINDOW_MS = 30 * DAY_MS;
const PERFORMANCE_WINDOW_MS = 14 * DAY_MS;

export async function createJsonBackup() {
  const latestMigration = PG_MIGRATIONS.at(-1)?.name ?? null;
  const data: Record<string, unknown> = {
    format: "lexiloop-json-backup",
    version: 3,
    database: "postgresql",
    appVersion: "1.0.0",
    schemaVersion: latestMigration,
    migrations: PG_MIGRATIONS.map((migration) => migration.name),
    exportedAt: new Date().toISOString(),
  };
  for (const table of TABLES) {
    const rows = await sqlite.prepare(`SELECT * FROM ${table}`).all() as Record<string, unknown>[];
    data[table] = table === "settings"
      ? rows.filter((row) => row.key !== CLOUD_SYNC_SERVER_SETTINGS_KEY)
      : rows;
  }
  return data;
}

function parseJsonBackup(raw: string): Record<BackupTable, Record<string, unknown>[]> {
  if (raw.length > MAX_BACKUP_BYTES) {
    throw new ApiError("BACKUP_TOO_LARGE", `备份文件过大（${(raw.length / 1024 / 1024).toFixed(1)}MB），上限 ${MAX_BACKUP_BYTES / 1024 / 1024}MB。`);
  }
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw) as unknown;
  } catch {
    throw new ApiError("BACKUP_INVALID_JSON", "备份文件不是有效的 JSON。");
  }
  if (!parsed || typeof parsed !== "object") throw new ApiError("BACKUP_INVALID_FORMAT", "备份格式无效。");
  const data = parsed as Record<string, unknown>;
  if (data.format !== "lexiloop-json-backup") throw new ApiError("BACKUP_INVALID_FORMAT", "不是 LexiLoop 备份文件（format 不匹配）。");
  if (typeof data.version !== "number") throw new ApiError("BACKUP_INVALID_FORMAT", "备份版本缺失。");

  const tables: Record<string, Record<string, unknown>[]> = {};
  for (const table of TABLES) {
    const value = data[table];
    if (value === undefined) {
      tables[table] = [];
      continue;
    }
    if (!Array.isArray(value)) throw new ApiError("BACKUP_INVALID_FORMAT", `表 ${table} 不是数组。`);
    for (const row of value) {
      if (!row || typeof row !== "object" || Array.isArray(row)) {
        throw new ApiError("BACKUP_INVALID_FORMAT", `表 ${table} 包含非法行。`);
      }
    }
    tables[table] = value as Record<string, unknown>[];
  }
  return tables as Record<BackupTable, Record<string, unknown>[]>;
}

function escapeIdentifier(name: string): string {
  return `"${name.replace(/"/g, '""')}"`;
}

function normalizeCellValue(table: string, column: string, value: unknown): unknown {
  if (value === undefined) return null;
  if (typeof value === "boolean" && BOOLEAN_INT_COLUMNS[table]?.has(column)) {
    return value ? 1 : 0;
  }
  return value;
}

async function actualTableColumns(table: string): Promise<Set<string>> {
  const rows = await sqlite
    .prepare(
      `SELECT column_name FROM information_schema.columns
       WHERE table_schema = current_schema() AND table_name = ?`,
    )
    .all(table) as { column_name: string }[];
  return new Set(rows.map((row) => row.column_name));
}

async function recomputeAllWordReviewStats(now: number): Promise<void> {
  const since30 = now - MASTERY_WINDOW_MS;
  const since14 = now - PERFORMANCE_WINDOW_MS;
  await sqlite.exec("DELETE FROM word_review_stats");
  await sqlite
    .prepare(
      `INSERT INTO word_review_stats (
         word_id, total_reviews, correct_reviews,
         recent_again_30d, recent_again_14d, recent_wrong_14d, recent_hard_14d,
         total_duration_ms, duration_count, last_reviewed_at, updated_at
       )
       SELECT
         word_id,
         count(*),
         coalesce(sum(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END), 0),
         coalesce(sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
         coalesce(sum(CASE WHEN rating = 'AGAIN' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
         coalesce(sum(CASE WHEN is_correct = 0 AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
         coalesce(sum(CASE WHEN rating = 'HARD' AND reviewed_at >= ? THEN 1 ELSE 0 END), 0),
         coalesce(sum(CASE WHEN duration_ms > 0 THEN duration_ms ELSE 0 END), 0),
         coalesce(sum(CASE WHEN duration_ms > 0 THEN 1 ELSE 0 END), 0),
         max(reviewed_at),
         ?
       FROM review_logs
       GROUP BY word_id`,
    )
    .run(since30, since14, since14, since14, now);
}

/**
 * Restore from a JSON backup string. Replaces all existing data.
 * - Filters columns by `backup ∩ information_schema.columns` so cross-version backups never crash.
 * - Recomputes materialized `word_review_stats` from `review_logs`.
 * - Rotates `cloudSyncServer.datasetEpoch` so connected Flutter clients fall back to full merge.
 */
export async function restoreJsonBackup(raw: string): Promise<{ restoredTables: BackupTable[]; rowCounts: Record<string, number> }> {
  const tables = parseJsonBackup(raw);
  const rowCounts: Record<string, number> = {};
  for (const t of TABLES) rowCounts[t] = tables[t].length;

  await sqlite.transaction(async () => {
    await sqlite.exec(`TRUNCATE ${RESTORE_ORDER.map(escapeIdentifier).join(", ")} CASCADE`);

    const insertOrder = [...RESTORE_ORDER].reverse() as BackupTable[];
    for (const table of insertOrder) {
      const rows = tables[table];
      if (rows.length === 0) continue;

      const validColumns = await actualTableColumns(table);
      const columns = Object.keys(rows[0]!).filter((col) => validColumns.has(col));
      if (columns.length === 0) continue;
      const colList = columns.map(escapeIdentifier).join(", ");

      const BATCH_SIZE = 50;
      for (let i = 0; i < rows.length; i += BATCH_SIZE) {
        const chunk = rows.slice(i, i + BATCH_SIZE);
        const placeholders: string[] = [];
        const params: unknown[] = [];
        let idx = 1;
        for (const row of chunk) {
          const rowPlaces = columns.map(() => `$${idx++}`);
          placeholders.push(`(${rowPlaces.join(", ")})`);
          for (const col of columns) {
            params.push(normalizeCellValue(table, col, row[col]));
          }
        }
        await sqlite
          .prepare(`INSERT INTO ${escapeIdentifier(table)} (${colList}) VALUES ${placeholders.join(", ")} ON CONFLICT DO NOTHING`)
          .run(...params);
      }
    }

    for (const { table, column } of SERIAL_SEQUENCES) {
      await sqlite.exec(
        `SELECT setval(pg_get_serial_sequence('${table}', '${column}'), COALESCE((SELECT MAX(${escapeIdentifier(column)}) FROM ${escapeIdentifier(table)}), 0) + 1, false)`,
      );
    }

    await recomputeAllWordReviewStats(Date.now());
  })();

  await rotateServerDatasetEpoch({ clearWatermarks: true });
  invalidateSettingsCache();

  return { restoredTables: [...TABLES], rowCounts };
}
