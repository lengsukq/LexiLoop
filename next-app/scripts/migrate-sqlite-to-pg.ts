/**
 * One-time script: migrate all data from a SQLite backup file to the remote PostgreSQL database.
 *
 * Usage:
 *   npx tsx scripts/migrate-sqlite-to-pg.ts /path/to/backup.sqlite
 *
 * Requires: sqlite3 CLI available on PATH, DATABASE_URL in .env
 */
import { execFileSync } from "node:child_process";
import { Pool, types as pgTypes } from "pg";
import { resolve } from "node:path";

process.loadEnvFile(resolve(import.meta.dirname, "../.env"));

pgTypes.setTypeParser(pgTypes.builtins.INT8, (v) => Number(v));
pgTypes.setTypeParser(pgTypes.builtins.NUMERIC, (v) => Number(v));

const sqlitePathArg = process.argv[2];
if (!sqlitePathArg) {
  console.error("Usage: npx tsx scripts/migrate-sqlite-to-pg.ts <sqlite-file>");
  process.exit(1);
}
const sqlitePath: string = sqlitePathArg;

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  console.error("DATABASE_URL is required in .env");
  process.exit(1);
}

// Tables in FK-dependency order (parents before children).
const TABLES_IN_ORDER = [
  "settings",
  "words",
  "word_contents",
  "word_review_stats",
  "study_sessions",
  "study_session_items",
  "review_cards",
  "review_logs",
  "wrong_word_states",
  "import_previews",
  "import_batches",
  "import_rows",
  "initialization_jobs",
  "provider_attempts",
  "worker_heartbeats",
  "daily_ai_suggestions",
  "manual_previews",
  "game_high_scores",
] as const;

function readTable(table: string): Record<string, unknown>[] {
  // Only allow known table names (validated against TABLES_IN_ORDER)
  if (!TABLES_IN_ORDER.includes(table as (typeof TABLES_IN_ORDER)[number])) {
    throw new Error(`Unknown table: ${table}`);
  }
  const raw = execFileSync(
    "sqlite3",
    ["-json", sqlitePath, `SELECT * FROM ${table}`],
    { maxBuffer: 64 * 1024 * 1024, encoding: "utf-8" },
  ).trim();
  if (!raw) return [];
  return JSON.parse(raw) as Record<string, unknown>[];
}

function normalizePgUrl(url: string): string {
  try {
    const parsed = new URL(url);
    const params = new URLSearchParams(parsed.search);
    params.delete("channel_binding");
    parsed.search = params.toString();
    return parsed.toString();
  } catch {
    return url;
  }
}

async function main() {
  console.log(`📂 SQLite file: ${sqlitePath}`);
  console.log(`🌐 PostgreSQL: ${databaseUrl!.replace(/:[^:@]+@/, ":***@")}`);
  console.log("");

  const pool = new Pool({
    connectionString: normalizePgUrl(databaseUrl!),
    max: 5,
    connectionTimeoutMillis: 15000,
    ssl: { rejectUnauthorized: true },
  });

  // 1. Ensure schema exists
  console.log("⚙️  Applying PG migrations (ensure schema)...");
  const { applyPgMigrations } = await import("../src/db/migrate-pg");
  await applyPgMigrations(pool);
  console.log("   Schema ready.\n");

  // 2. Always start clean — truncate all tables
  console.log("🗑️  Truncating existing tables for clean import...");
  await pool.query(`TRUNCATE
    provider_attempts, initialization_jobs, import_rows, import_batches, import_previews,
    wrong_word_states, review_logs, review_cards, study_session_items, study_sessions,
    word_review_stats, word_contents, manual_previews, game_high_scores,
    daily_ai_suggestions, worker_heartbeats, settings, words
    CASCADE`);
  console.log("   Done.\n");

  // 3. Import each table using multi-row batch inserts
  const BATCH_SIZE = 50;

  // Pre-load valid initialization_jobs IDs for FK cleanup
  const validJobIds = new Set(
    readTable("initialization_jobs").map((r) => r.id as number),
  );

  for (const table of TABLES_IN_ORDER) {
    const rows = readTable(table);
    if (rows.length === 0) {
      console.log(`   ${table}: 0 rows (skipped)`);
      continue;
    }

    // Fix orphaned FK references (SQLite doesn't enforce FKs by default)
    if (table === "provider_attempts") {
      let fixed = 0;
      for (const row of rows) {
        if (row.initialization_job_id !== null && !validJobIds.has(row.initialization_job_id as number)) {
          row.initialization_job_id = null;
          fixed++;
        }
      }
      if (fixed) console.log(`   provider_attempts: nullified ${fixed} orphaned job refs`);
    }

    const columns = Object.keys(rows[0]!);
    const colList = columns.map((c) => `"${c}"`).join(", ");

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      for (let i = 0; i < rows.length; i += BATCH_SIZE) {
        const chunk = rows.slice(i, i + BATCH_SIZE);
        // Build multi-row VALUES clause
        const valueClauses: string[] = [];
        const params: unknown[] = [];
        let paramIdx = 1;
        for (const row of chunk) {
          const placeholders = columns.map(() => `$${paramIdx++}`);
          valueClauses.push(`(${placeholders.join(", ")})`);
          for (const col of columns) {
            const v = row[col];
            params.push(v === null || v === undefined ? null : v);
          }
        }
        const sql = `INSERT INTO "${table}" (${colList}) VALUES ${valueClauses.join(", ")} ON CONFLICT DO NOTHING`;
        await client.query(sql, params);
      }
      await client.query("COMMIT");
      console.log(`   ${table}: ${rows.length} rows ✓`);
    } catch (error) {
      await client.query("ROLLBACK");
      console.error(`   ${table}: FAILED —`, (error as Error).message);
      console.error("   Aborting migration.");
      await pool.end();
      process.exit(1);
    } finally {
      client.release();
    }
  }

  // 4. Reset sequences for BIGSERIAL columns
  console.log("\n🔧 Resetting sequences...");
  const serialTables = [
    { table: "words", col: "id" },
    { table: "study_sessions", col: "id" },
    { table: "study_session_items", col: "id" },
    { table: "review_logs", col: "id" },
    { table: "import_batches", col: "id" },
    { table: "import_rows", col: "id" },
    { table: "initialization_jobs", col: "id" },
    { table: "provider_attempts", col: "id" },
    { table: "game_high_scores", col: "id" },
  ];
  for (const { table, col } of serialTables) {
    await pool.query(
      `SELECT setval(pg_get_serial_sequence('"${table}"', '${col}'), COALESCE(MAX("${col}"), 0) + 1, false) FROM "${table}"`,
    );
  }
  console.log("   Sequences reset.\n");

  // 5. Verify
  console.log("📊 Verification:");
  for (const table of TABLES_IN_ORDER) {
    const result = await pool.query(`SELECT COUNT(*)::int AS cnt FROM "${table}"`);
    console.log(`   ${table}: ${result.rows[0].cnt} rows`);
  }

  await pool.end();
  console.log("\n✅ Migration complete!");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
