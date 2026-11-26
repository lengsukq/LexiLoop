import { applyPgMigrations } from "@/db/migrate-pg";
import { createPgFacade, type SqliteLikeDatabase } from "@/db/executor";

const globalDb = globalThis as typeof globalThis & { __lexiloopDbFacade?: SqliteLikeDatabase };

function createBundle(): SqliteLikeDatabase {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) throw new Error("DATABASE_URL is required (PostgreSQL)");
  return createPgFacade(databaseUrl, (pool) => applyPgMigrations(pool));
}

function getBundle(): SqliteLikeDatabase {
  const existing = globalDb.__lexiloopDbFacade;
  if (existing) return existing;
  const bundle = createBundle();
  globalDb.__lexiloopDbFacade = bundle;
  return bundle;
}

const bundleProxy = new Proxy({} as SqliteLikeDatabase, {
  get(_target, prop) {
    const bundle = getBundle();
    const value = (bundle as unknown as Record<string, unknown>)[prop as string];
    return typeof value === "function" ? (value as (...args: unknown[]) => unknown).bind(bundle) : value;
  },
});

/**
 * PostgreSQL-backed database facade. The name `sqlite` is kept for
 * backwards compatibility at call sites (42+ imports) — it is always
 * PostgreSQL. Prefer `import { db } ...` in new code.
 */
export const sqlite: SqliteLikeDatabase = bundleProxy;
export const db: SqliteLikeDatabase = bundleProxy;
