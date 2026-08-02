import { sqlite } from "@/db/client";
import { PG_MIGRATIONS } from "@/db/migrations/pg";

const TABLES = [
  "words", "word_contents", "review_cards", "review_logs", "wrong_word_states",
  "import_batches", "import_rows", "initialization_jobs", "provider_attempts",
  "study_sessions", "study_session_items", "settings",
] as const;

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
