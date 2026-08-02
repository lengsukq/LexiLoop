import { applyPgMigrations } from "@/db/migrate-pg";
import { createPgFacade, type SqliteLikeDatabase } from "@/db/executor";

const globalDb = globalThis as typeof globalThis & { __lexiloopDbFacade?: SqliteLikeDatabase };

function createBundle(): SqliteLikeDatabase {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) throw new Error("DATABASE_URL is required in PostgreSQL mode");
  return createPgFacade(databaseUrl, (pool) => applyPgMigrations(pool));
}

const bundle = globalDb.__lexiloopDbFacade ?? createBundle();
if (process.env.NODE_ENV !== "production") globalDb.__lexiloopDbFacade = bundle;

/**
 * Unified database handle backed by PostgreSQL. The name is kept as `sqlite`
 * for historical reasons; it always dispatches to the Postgres driver now.
 */
export const sqlite = bundle;
