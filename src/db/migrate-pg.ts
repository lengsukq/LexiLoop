import { Pool } from "pg";
import { PG_MIGRATIONS } from "@/db/migrations/pg";

const MIGRATION_TABLE = "_lexiloop_migrations";

/**
 * Applies pending PostgreSQL migrations inside per-migration transactions so a
 * failed DDL step never leaves a half-applied schema behind.
 */
export async function applyPgMigrations(pool: Pool): Promise<void> {
  await pool.query(`CREATE TABLE IF NOT EXISTS ${MIGRATION_TABLE} (
    name TEXT PRIMARY KEY,
    applied_at BIGINT NOT NULL
  )`);

  for (const migration of PG_MIGRATIONS) {
    const applied = await pool.query(
      `SELECT 1 FROM ${MIGRATION_TABLE} WHERE name = $1`,
      [migration.name],
    );
    if (applied.rowCount) continue;

    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query(migration.sql);
      await client.query(
        `INSERT INTO ${MIGRATION_TABLE}(name, applied_at) VALUES ($1, $2)`,
        [migration.name, Date.now()],
      );
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }
  }
}
