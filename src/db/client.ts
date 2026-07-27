import Database from "better-sqlite3";
import { drizzle } from "drizzle-orm/better-sqlite3";
import * as schema from "@/db/schema";
import { applyMigrations } from "@/db/migrate";

type DbBundle = {
  sqlite: Database.Database;
  db: ReturnType<typeof drizzle<typeof schema>>;
};

const globalDb = globalThis as typeof globalThis & { __lexiloopDb?: DbBundle };

function createBundle(): DbBundle {
  const databasePath = process.env.DATABASE_PATH ?? "./data/app.sqlite";
  const sqlite = new Database(databasePath);
  sqlite.pragma("journal_mode = WAL");
  sqlite.pragma("foreign_keys = ON");
  sqlite.pragma("busy_timeout = 5000");
  sqlite.pragma("synchronous = NORMAL");
  applyMigrations(sqlite);
  return { sqlite, db: drizzle(sqlite, { schema }) };
}

const bundle = globalDb.__lexiloopDb ?? createBundle();
if (process.env.NODE_ENV !== "production") globalDb.__lexiloopDb = bundle;

export const sqlite = bundle.sqlite;
export const db = bundle.db;
