import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import { MIGRATIONS } from "@/db/migration-sources";

export function applyMigrations(sqlite: Database.Database): void {
  sqlite.exec(`CREATE TABLE IF NOT EXISTS _lexiloop_migrations (
    name TEXT PRIMARY KEY,
    applied_at INTEGER NOT NULL
  )`);
  const applied = sqlite.prepare("SELECT 1 FROM _lexiloop_migrations WHERE name = ?");
  const record = sqlite.prepare("INSERT INTO _lexiloop_migrations(name, applied_at) VALUES (?, ?)");
  sqlite.transaction(() => {
    for (const migration of MIGRATIONS) {
      if (applied.get(migration.name)) continue;
      sqlite.exec(migration.sql);
      record.run(migration.name, Date.now());
    }
  }).immediate();
}

export function migrateDatabase(databasePath: string): void {
  fs.mkdirSync(path.dirname(path.resolve(databasePath)), { recursive: true });
  const sqlite = new Database(databasePath);
  try {
    sqlite.pragma("journal_mode = WAL");
    sqlite.pragma("foreign_keys = ON");
    sqlite.pragma("busy_timeout = 5000");
    sqlite.pragma("synchronous = NORMAL");
    applyMigrations(sqlite);
  } finally {
    sqlite.close();
  }
}
