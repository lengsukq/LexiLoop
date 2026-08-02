import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeEach } from "vitest";

// Load .env and .env.local so DATABASE_URL is available even when the test runner
// does not apply Next.js-style environment file loading.
(function loadLocalEnv(): void {
  for (const envName of [".env", ".env.local"]) {
    const envFile = path.join(process.cwd(), envName);
    if (!fs.existsSync(envFile)) continue;
    for (const line of fs.readFileSync(envFile, "utf8").split("\n")) {
      const match = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
      if (!match) continue;
      const [key, value] = [match[1], match[2]];
      if (key && value !== undefined && !(key in process.env)) process.env[key] = value;
    }
  }
})();

// Tests always run against PostgreSQL, isolated from the production database.
// When TEST_DATABASE_URL is unset, derive a sibling database from DATABASE_URL
// (e.g. <project>/neondb -> <project>/neondb_test) so tests never touch user data.
const productionUrl = process.env.DATABASE_URL;
if (productionUrl) {
  process.env.DATABASE_URL =
    process.env.TEST_DATABASE_URL ?? productionUrl.replace(/\/[^/?]+(\?|$)/, "/neondb_test$1");
}

const backupDir = path.join(os.tmpdir(), `lexiloop-backups-${process.pid}`);
process.env.BACKUP_DIR = backupDir;
process.env.DICTIONARY_API_ENABLED = "false";
process.env.MYMEMORY_ENABLED = "false";

const ALL_TABLES = [
  "provider_attempts",
  "initialization_jobs",
  "daily_ai_suggestions",
  "import_rows",
  "import_batches",
  "import_previews",
  "review_logs",
  "study_session_items",
  "study_sessions",
  "wrong_word_states",
  "review_cards",
  "word_review_stats",
  "word_contents",
  "words",
  "worker_heartbeats",
  "settings",
  "manual_previews",
  "game_high_scores",
];

beforeEach(async () => {
  const { sqlite } = await import("@/db/client");
  for (const table of ALL_TABLES) await sqlite.exec(`DELETE FROM ${table}`);
});

afterAll(async () => {
  const { sqlite } = await import("@/db/client");
  await sqlite.close();
  delete (globalThis as { __lexiloopDbFacade?: unknown }).__lexiloopDbFacade;
  fs.rmSync(backupDir, { recursive: true, force: true });
});
