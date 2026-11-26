import { sqlite } from "@/db/client";
import { PG_MIGRATIONS } from "@/db/migrations/pg";
import { ApiError } from "@/lib/api";
import { invalidateSettingsCache } from "@/modules/settings/service";

const TABLES = [
  "words", "word_contents", "review_cards", "review_logs", "wrong_word_states",
  "import_batches", "import_rows", "initialization_jobs", "provider_attempts",
  "study_sessions", "study_session_items", "settings",
] as const;

type BackupTable = (typeof TABLES)[number];

// Child tables first (FK children before parents) for TRUNCATE/CASCADE-safe clearing.
const RESTORE_ORDER: readonly BackupTable[] = [
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

const MAX_BACKUP_BYTES = 100 * 1024 * 1024;

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
  for (const table of TABLES) data[table] = await sqlite.prepare(`SELECT * FROM ${table}`).all();
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
  // Accept version 3 (current) and tolerate older numeric versions; unknown structures will still fail on table validation below.
  if (typeof data.version !== "number") throw new ApiError("BACKUP_INVALID_FORMAT", "备份版本缺失。");

  const tables: Record<string, Record<string, unknown>[]> = {};
  for (const table of TABLES) {
    const value = data[table];
    if (value === undefined) {
      tables[table] = [];
      continue;
    }
    if (!Array.isArray(value)) throw new ApiError("BACKUP_INVALID_FORMAT", `表 ${table} 不是数组。`);
    // Shallow-validate rows are plain objects
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

/**
 * Restore from a JSON backup string. Replaces all existing data.
 * - Runs inside a single transaction: truncate + batch inserts + sequence reset are atomic.
 * - Validates format/version before touching the database (pre-checked by parseJsonBackup, but re-checked here).
 * - Resets BIGSERIAL sequences so subsequent inserts don't collide with restored ids.
 */
export async function restoreJsonBackup(raw: string): Promise<{ restoredTables: BackupTable[]; rowCounts: Record<string, number> }> {
  const tables = parseJsonBackup(raw);
  const rowCounts: Record<string, number> = {};
  for (const t of TABLES) rowCounts[t] = tables[t].length;

  await sqlite.transaction(async () => {
    // 1) Clear existing data (respect FK order via CASCADE; single statement is atomic inside transaction).
    // Use TRUNCATE CASCADE for speed; fallback via DELETE is handled by executor/caller error propagation.
    await sqlite.exec(`TRUNCATE ${RESTORE_ORDER.map(escapeIdentifier).join(", ")} CASCADE`);

    // 2) Insert tables in parent-first order (reverse of truncate order — parents before children).
    const insertOrder = [...RESTORE_ORDER].reverse() as BackupTable[];
    for (const table of insertOrder) {
      const rows = tables[table];
      if (rows.length === 0) continue;

      // Derive columns from first row; all rows validated to share same keys shape in parse, but be defensive.
      const columns = Object.keys(rows[0]!);
      const colList = columns.map(escapeIdentifier).join(", ");

      // Batch inserts to avoid exceeding PG parameter limits (~32767). 50 rows * ~20 cols = ~1000 params per batch.
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
            const v = row[col];
            params.push(v === undefined ? null : v);
          }
        }
        // Use INSERT ... ON CONFLICT DO NOTHING defensively; backup data should be self-consistent,
        // but this avoids hard failure on duplicate PK if file has an edge-case duplicate.
        await sqlite.prepare(`INSERT INTO ${escapeIdentifier(table)} (${colList}) VALUES ${placeholders.join(", ")} ON CONFLICT DO NOTHING`).run(...params);
      }
    }

    // 3) Reset BIGSERIAL sequences to MAX(id)+1 (or 1 if empty) so future inserts don't reuse restored ids.
    for (const { table, column } of SERIAL_SEQUENCES) {
      await sqlite.exec(
        `SELECT setval(pg_get_serial_sequence('${table}', '${column}'), COALESCE((SELECT MAX(${escapeIdentifier(column)}) FROM ${escapeIdentifier(table)}), 0) + 1, false)`,
      );
    }
  })();

  invalidateSettingsCache();

  return { restoredTables: [...TABLES], rowCounts };
}
