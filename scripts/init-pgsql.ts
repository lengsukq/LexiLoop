import Database from "better-sqlite3";
import { createInterface } from "node:readline";
import { Pool } from "pg";
import { loadLocalEnv } from "./load-local-env";
import { normalizePgUrl } from "../src/db/executor";
import { applyPgMigrations } from "../src/db/migrate-pg";

loadLocalEnv();

const SOURCE_PATH = process.env.SQLITE_SOURCE_PATH ?? "c:/Users/Su/Downloads/app.sqlite";

// Insertion order follows foreign-key dependencies (parents before children).
const TABLES_IN_FK_ORDER = [
  "settings",
  "words",
  "word_contents",
  "wrong_word_states",
  "review_cards",
  "word_review_stats",
  "daily_ai_suggestions",
  "manual_previews",
  "import_previews",
  "import_batches",
  "import_rows",
  "initialization_jobs",
  "provider_attempts",
  "study_sessions",
  "study_session_items",
  "review_logs",
  "game_high_scores",
  "worker_heartbeats",
] as const;

const AUTOINCREMENT_TABLES = [
  "words",
  "study_sessions",
  "study_session_items",
  "review_logs",
  "import_batches",
  "import_rows",
  "initialization_jobs",
  "provider_attempts",
  "game_high_scores",
] as const;

function databaseUrl(): string {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is required for pgsql seeding");
  // Neon's transaction pooler (PgBouncer) rejects multi-row parameterized
  // INSERTs, so the seed connects directly to the compute endpoint instead.
  const direct = url.replace(/(ep-[a-z0-9-]+)-pooler(\.[^/?]+)/, "$1$2");
  return normalizePgUrl(direct);
}

function sqliteSource(): Database.Database {
  return new Database(SOURCE_PATH, { readonly: true });
}

async function confirmDestructive(): Promise<void> {
  if (process.env.SEED_FORCE === "1") return;
  const readline = createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise<string>((resolve) =>
    readline.question("???? pgsql ??????????????? yes ??: ", resolve),
  );
  readline.close();
  if (answer.trim().toLowerCase() !== "yes") {
    console.log("????");
    process.exit(0);
  }
}

async function integerColumns(pool: Pool, table: string): Promise<Set<string>> {
  const result = await pool.query(
    "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = $1",
    [table],
  );
  return new Set(
    result.rows
      .filter((row) => ["bigint", "integer", "smallint"].includes(row.data_type))
      .map((row) => row.column_name),
  );
}

async function copyTable(
  pool: Pool,
  source: Database.Database,
  table: string,
  keepRow: (row: Record<string, unknown>) => boolean = () => true,
): Promise<{ copied: number; skipped: number }> {
  const columns = (
    source.prepare(`PRAGMA table_info("${table}")`).all() as Array<{ name: string }>
  ).map((column) => column.name);
  const rows = source.prepare(`SELECT * FROM "${table}"`).all() as Record<string, unknown>[];
  const kept = rows.filter(keepRow);
  const skipped = rows.length - kept.length;
  if (kept.length === 0) return { copied: 0, skipped };

  const integerColumnNames = await integerColumns(pool, table);
  const columnList = columns.join(", ");
  const BATCH_SIZE = 500;

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    for (let offset = 0; offset < kept.length; offset += BATCH_SIZE) {
      const batch = kept.slice(offset, offset + BATCH_SIZE);
      const valueGroups = batch.map((_, rowIndex) => {
        const base = rowIndex * columns.length;
        const placeholders = columns.map((_, colIndex) => `$${base + colIndex + 1}`).join(", ");
        return `(${placeholders})`;
      });
      const insertSql = `INSERT INTO "${table}" (${columnList}) VALUES ${valueGroups.join(", ")}`;
      const values = batch.flatMap((row) =>
        columns.map((column) => {
          const raw = row[column] === undefined ? null : row[column];
          if (typeof raw === "number" && !Number.isInteger(raw) && integerColumnNames.has(column)) {
            return Math.trunc(raw);
          }
          return raw;
        }),
      );
      await client.query(insertSql, values);
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  return { copied: kept.length, skipped };
}

async function syncSequences(pool: Pool): Promise<void> {
  const client = await pool.connect();
  try {
    for (const table of AUTOINCREMENT_TABLES) {
      const sequence = await client.query("SELECT pg_get_serial_sequence($1, 'id') AS name", [table]);
      const sequenceName = sequence.rows[0]?.name as string | undefined;
      if (!sequenceName) continue;
      const maxRow = await client.query(`SELECT COALESCE(MAX(id), 0) AS max_id FROM "${table}"`);
      const maxId = Number(maxRow.rows[0]?.max_id ?? 0);
      await client.query("SELECT setval($1, GREATEST($2, 1))", [sequenceName, maxId]);
      console.log(`  [seq] ${table} -> ${maxId}`);
    }
  } finally {
    client.release();
  }
}

async function main(): Promise<void> {
  const url = databaseUrl();
  await confirmDestructive();

  const pool = new Pool({ connectionString: url });
  const source = sqliteSource();
  try {
    console.log("[1/4] ?? PostgreSQL ??...");
    await applyPgMigrations(pool);

    console.log("[2/4] ?????...");
    await pool.query(`TRUNCATE ${TABLES_IN_FK_ORDER.join(", ")} RESTART IDENTITY CASCADE`);

    console.log("[3/4] ? SQLite ????...");
    // The SQLite source carries orphaned provider_attempts rows whose
    // initialization_job_id no longer exists (1341 rows). They are skipped so
    // PostgreSQL FK constraints stay satisfiable; the app only ever joins these
    // through existing jobs, so dropped orphans are harmless.
    const validJobIds = new Set(
      (source.prepare("SELECT id FROM initialization_jobs").all() as Array<{ id: number }>).map((row) => row.id),
    );
    const keepProviderAttempt = (row: Record<string, unknown>): boolean => {
      const jobId = row.initialization_job_id;
      return jobId === null || jobId === undefined || validJobIds.has(Number(jobId));
    };

    const summary: Array<{ table: string; copied: number; skipped: number; sqliteCount: number; pgCount: number }> = [];
    for (const table of TABLES_IN_FK_ORDER) {
      const sqliteCount = (source.prepare(`SELECT COUNT(*) AS c FROM "${table}"`).get() as { c: number }).c;
      const result = await copyTable(pool, source, table, table === "provider_attempts" ? keepProviderAttempt : undefined);
      const pgCount = Number((await pool.query(`SELECT COUNT(*) AS c FROM "${table}"`)).rows[0]?.c ?? 0);
      summary.push({ table, copied: result.copied, skipped: result.skipped, sqliteCount, pgCount });
    }

    console.log("[4/4] ??????...");
    await syncSequences(pool);

    console.log("\n=== ???? ===");
    let failed = false;
    for (const row of summary) {
      const matched = row.copied === row.sqliteCount - row.skipped && row.pgCount === row.copied;
      if (!matched) failed = true;
      const skippedNote = row.skipped > 0 ? ` (???? ${row.skipped})` : "";
      console.log(
        `${matched ? "OK  " : "FAIL"} ${row.table.padEnd(24)} sqlite=${row.sqliteCount} copied=${row.copied} pg=${row.pgCount}${skippedNote}`,
      );
    }
    if (failed) {
      console.error("\n?????????????");
      process.exit(1);
    }
    console.log("\n???????????? SQLite ???");
  } finally {
    source.close();
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
