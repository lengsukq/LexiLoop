import { PGlite, types as pgliteTypes, type Transaction } from "@electric-sql/pglite";
import { PG_MIGRATIONS } from "@/db/migrations/pg";
import {
  rewriteSql,
  toNumber,
  type PreparedStatement,
  type SqliteLikeDatabase,
  type SqliteLikeTransaction,
} from "@/db/types";

const MIGRATION_TABLE = "_lexiloop_migrations";

async function applyPgliteMigrations(pg: PGlite): Promise<void> {
  await pg.exec(`CREATE TABLE IF NOT EXISTS ${MIGRATION_TABLE} (
    name TEXT PRIMARY KEY,
    applied_at BIGINT NOT NULL
  )`);

  for (const migration of PG_MIGRATIONS) {
    const applied = await pg.query(
      `SELECT 1 FROM ${MIGRATION_TABLE} WHERE name = $1`,
      [migration.name],
    );
    if (applied.rows.length > 0) continue;

    await pg.transaction(async (tx) => {
      // PG_MIGRATIONS contain multi-statement DDL scripts; use Simple Query `exec`.
      await tx.exec(migration.sql);
      await tx.query(
        `INSERT INTO ${MIGRATION_TABLE}(name, applied_at) VALUES ($1, $2)`,
        [migration.name, Date.now()],
      );
    });
  }
}

export interface PgliteFacade extends SqliteLikeDatabase {
  ensureReady(): Promise<void>;
}

/**
 * Creates a PGlite-backed `SqliteLikeDatabase` facade for Browser Local Mode
 * (`idb://lexiloop-local`) and unit tests (`memory://`).
 */
export function createPgliteFacade(
  dataDir = "idb://lexiloop-local",
  options: { relaxedDurability?: boolean } = {},
): PgliteFacade {
  let pgInstance: PGlite | null = null;
  let activeTx: Transaction | null = null;
  let txChain: Promise<void> = Promise.resolve();

  const readyPromise = (async () => {
    const pg = await PGlite.create(dataDir, {
      relaxedDurability: options.relaxedDurability ?? true,
      parsers: {
        [pgliteTypes.INT8]: (value) => Number(value),
        [pgliteTypes.NUMERIC]: (value) => Number(value),
      },
    });
    await applyPgliteMigrations(pg);
    pgInstance = pg;
    return pg;
  })().catch((error) => {
    console.error("[LexiLoop Local] PGlite initialization failed:", error);
    throw error;
  });

  async function getPg(): Promise<PGlite> {
    if (pgInstance) return pgInstance;
    return readyPromise;
  }

  async function runQuery(sql: string, params: unknown[] = []) {
    const pg = await getPg();
    if (activeTx) return activeTx.query(sql, params);
    return pg.query(sql, params);
  }

  async function runExec(sql: string): Promise<void> {
    if (/^\s*PRAGMA\b/i.test(sql)) return;
    const pg = await getPg();
    if (activeTx) {
      await activeTx.exec(sql);
      return;
    }
    await pg.exec(sql);
  }

  const prepare = (sql: string): PreparedStatement => {
    const rewritten = rewriteSql(sql);
    const isInsert = /^\s*INSERT\b/i.test(sql);
    const hasReturning = /\bRETURNING\b/i.test(rewritten);
    const runSql =
      isInsert && !hasReturning ? `${rewritten.replace(/;\s*$/, "")} RETURNING *` : rewritten;

    return {
      get: async (...params) => (await runQuery(rewritten, params)).rows[0],
      all: async (...params) => (await runQuery(rewritten, params)).rows,
      run: async (...params) => {
        const result = await runQuery(runSql, params);
        const rows = result.rows as Array<Record<string, unknown>>;
        return {
          changes: result.affectedRows ?? result.rowCount ?? 0,
          lastInsertRowid: toNumber(rows[0]?.id),
        };
      },
    };
  };

  function enqueueTransaction<TResult>(fn: () => Promise<TResult>): Promise<TResult> {
    const previous = txChain;
    let release!: () => void;
    txChain = new Promise<void>((resolve) => {
      release = resolve;
    });

    return previous.then(async () => {
      try {
        const pg = await getPg();
        return await pg.transaction(async (tx) => {
          activeTx = tx;
          try {
            return await fn();
          } finally {
            activeTx = null;
          }
        });
      } finally {
        release();
      }
    });
  }

  const transaction = <TArgs extends unknown[], TResult>(
    fn: (...args: TArgs) => TResult | Promise<TResult>,
  ): SqliteLikeTransaction<TArgs, TResult> => {
    const run = async (args: TArgs): Promise<TResult> => {
      // Nested transaction() calls reuse the currently active transaction cleanly.
      if (activeTx) return (await fn(...args)) as TResult;
      return enqueueTransaction(async () => (await fn(...args)) as TResult);
    };
    const wrapper = ((...args: TArgs) => run(args)) as SqliteLikeTransaction<TArgs, TResult>;
    wrapper.immediate = (...args: TArgs) => run(args);
    wrapper.deferred = (...args: TArgs) => run(args);
    wrapper.exclusive = (...args: TArgs) => run(args);
    return wrapper;
  };

  return {
    mode: "postgres",
    ensureReady: async () => {
      await getPg();
    },
    prepare,
    exec: runExec,
    pragma: async () => undefined,
    transaction,
    close: async () => {
      const pg = pgInstance;
      pgInstance = null;
      if (pg && !pg.closed) await pg.close();
    },
    backup: async () => {
      throw new Error("SQLite file backup is unavailable — use JSON backup on Browser PGlite.");
    },
  };
}
