import { Pool } from "pg";
import { loadLocalEnv } from "./load-local-env";
import { normalizePgUrl } from "../src/db/executor";
import { applyPgMigrations } from "../src/db/migrate-pg";

loadLocalEnv();

async function main(): Promise<void> {
  const url = process.env.DATABASE_URL;
  if (!url) throw new Error("DATABASE_URL is required in PostgreSQL mode");
  const pool = new Pool({ connectionString: normalizePgUrl(url) });
  try {
    await applyPgMigrations(pool);
    console.log("[LexiLoop] migrations applied (postgres)");
  } finally {
    await pool.end();
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
