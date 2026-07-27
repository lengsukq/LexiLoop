import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterAll, beforeEach } from "vitest";

const databasePath = path.join(os.tmpdir(), `lexiloop-vitest-${process.pid}.sqlite`);
process.env.DATABASE_PATH = databasePath;
process.env.BACKUP_DIR = path.join(os.tmpdir(), `lexiloop-backups-${process.pid}`);
process.env.ECDICT_DATABASE_PATH = path.join(os.tmpdir(), `lexiloop-ecdict-${process.pid}.sqlite`);
process.env.DICTIONARY_API_ENABLED = "false";
process.env.MYMEMORY_ENABLED = "false";
process.env.ECDICT_ENABLED = "false";

beforeEach(async () => {
  const { sqlite } = await import("@/db/client");
  sqlite.exec("PRAGMA foreign_keys = OFF");
  for (const table of [
    "provider_attempts", "initialization_jobs", "import_rows", "import_batches", "import_previews",
    "review_logs", "study_session_items", "study_sessions", "wrong_word_states", "review_cards",
    "word_contents", "words", "worker_heartbeats", "settings",
  ]) sqlite.exec(`DELETE FROM ${table}`);
  sqlite.exec("PRAGMA foreign_keys = ON");
});

afterAll(async () => {
  const { sqlite } = await import("@/db/client");
  sqlite.close();
  for (const suffix of ["", "-wal", "-shm"]) fs.rmSync(`${databasePath}${suffix}`, { force: true });
  fs.rmSync(process.env.BACKUP_DIR!, { recursive: true, force: true });
});
