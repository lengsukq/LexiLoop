import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { sqlite } from "@/db/client";
import { MIGRATIONS } from "@/db/migration-sources";

const TABLES = [
  "words", "word_contents", "review_cards", "review_logs", "wrong_word_states",
  "import_batches", "import_rows", "initialization_jobs", "provider_attempts",
  "study_sessions", "study_session_items", "settings",
] as const;

export interface BackupValidation {
  valid: boolean;
  error?: string;
  appliedMigrations?: string[];
  pendingMigrations?: string[];
  latestSupportedMigration?: string;
}

function backupDir(): string {
  const directory = path.resolve(/* turbopackIgnore: true */ process.env.BACKUP_DIR ?? "./data/backups");
  fs.mkdirSync(directory, { recursive: true });
  return directory;
}

export async function createSqliteBackup(): Promise<{ path: string; filename: string }> {
  const filename = `lexiloop-${new Date().toISOString().replace(/[:.]/g, "-")}.sqlite`;
  const destination = path.join(backupDir(), `.download-${crypto.randomUUID()}.sqlite`);
  sqlite.pragma("wal_checkpoint(FULL)");
  await sqlite.backup(destination);
  return { path: destination, filename };
}

export function removeGeneratedBackup(filePath: string): void {
  const resolved = path.resolve(filePath);
  const directory = `${backupDir()}${path.sep}`;
  if (!resolved.startsWith(directory) || !path.basename(resolved).startsWith(".download-")) return;
  fs.rmSync(resolved, { force: true });
}

export function createJsonBackup() {
  const latestMigration = MIGRATIONS.at(-1)?.name ?? null;
  const data: Record<string, unknown> = {
    format: "lexiloop-json-backup",
    version: 2,
    appVersion: "1.0.0",
    schemaVersion: latestMigration,
    migrations: MIGRATIONS.map((migration) => migration.name),
    exportedAt: new Date().toISOString(),
  };
  for (const table of TABLES) data[table] = sqlite.prepare(`SELECT * FROM ${table}`).all();
  return data;
}

export function validateSqliteBackup(filePath: string): BackupValidation {
  let database: Database.Database | null = null;
  try {
    database = new Database(filePath, { readonly: true, fileMustExist: true });
    const integrity = database.pragma("integrity_check", { simple: true });
    if (integrity !== "ok") return { valid: false, error: `SQLite integrity_check: ${String(integrity)}` };
    const tables = new Set((database.prepare("SELECT name FROM sqlite_master WHERE type='table'").all() as Array<{ name: string }>).map((row) => row.name));
    for (const required of ["words", "word_contents", "review_cards", "settings", "_lexiloop_migrations"]) {
      if (!tables.has(required)) return { valid: false, error: `缺少必要数据表：${required}` };
    }

    const known = MIGRATIONS.map((migration) => migration.name);
    const knownSet = new Set<string>(known);
    const applied = (database.prepare("SELECT name FROM _lexiloop_migrations ORDER BY applied_at ASC").all() as Array<{ name: string }>).map((row) => row.name);
    if (!applied.includes("0000_initial.sql")) return { valid: false, error: "备份缺少 LexiLoop 初始迁移记录。" };
    const unknown = applied.filter((name) => !knownSet.has(name));
    if (unknown.length > 0) {
      return {
        valid: false,
        error: `备份来自更高版本的 LexiLoop，当前版本无法安全恢复：${unknown.join("、")}`,
        appliedMigrations: applied,
        latestSupportedMigration: known.at(-1),
      };
    }
    const pending = known.filter((name) => !applied.includes(name));
    return {
      valid: true,
      appliedMigrations: applied,
      pendingMigrations: pending,
      latestSupportedMigration: known.at(-1),
    };
  } catch (error) {
    return { valid: false, error: String(error) };
  } finally {
    database?.close();
  }
}

export function stageSqliteRestore(buffer: Buffer): {
  filename: string; sha256: string; pendingMigrations: string[]; latestSupportedMigration: string | null;
} {
  const directory = path.dirname(path.resolve(/* turbopackIgnore: true */ process.env.DATABASE_PATH ?? "./data/app.sqlite"));
  fs.mkdirSync(directory, { recursive: true });
  const temp = path.join(directory, `.restore-${crypto.randomUUID()}.sqlite`);
  fs.writeFileSync(temp, buffer, { mode: 0o600 });
  const validation = validateSqliteBackup(temp);
  if (!validation.valid) {
    fs.rmSync(temp, { force: true });
    throw new Error(validation.error ?? "备份文件无效");
  }
  const pending = path.join(directory, "restore-pending.sqlite");
  fs.rmSync(pending, { force: true });
  fs.renameSync(temp, pending);
  return {
    filename: path.basename(pending),
    sha256: crypto.createHash("sha256").update(buffer).digest("hex"),
    pendingMigrations: validation.pendingMigrations ?? [],
    latestSupportedMigration: validation.latestSupportedMigration ?? null,
  };
}
