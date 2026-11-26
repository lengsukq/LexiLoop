import { AsyncLocalStorage } from "node:async_hooks";
import { Pool, types as pgTypes } from "pg";
import {
  rewriteSql,
  toNumber,
  type DatabaseMode,
  type PreparedStatement,
  type RunResult,
  type SqliteLikeDatabase,
  type SqliteLikeTransaction,
} from "@/db/types";

export {
  rewriteSql,
  toNumber,
  type DatabaseMode,
  type PreparedStatement,
  type RunResult,
  type SqliteLikeDatabase,
  type SqliteLikeTransaction,
};

/** Strips connection parameters that node-postgres does not understand. */
export function normalizePgUrl(url: string): string {
  try {
    const parsed = new URL(url);
    const params = new URLSearchParams(parsed.search);
    params.delete("channel_binding");
    parsed.search = params.toString();
    return parsed.toString();
  } catch {
    return url;
  }
}

// ---- postgres backend ------------------------------------------------------

type TransactionConnection = { client: import("pg").PoolClient };

export function createPgFacade(
  connectionString: string,
  onInit?: (pool: Pool) => Promise<void>,
): SqliteLikeDatabase {
  // PG returns int8/numeric as strings; numbers keep JSON APIs and arithmetic working.
  pgTypes.setTypeParser(pgTypes.builtins.INT8, (value) => Number(value));
  pgTypes.setTypeParser(pgTypes.builtins.NUMERIC, (value) => Number(value));

  const isLocalhost = (() => { try { const u = new URL(normalizePgUrl(connectionString)); return u.hostname === "localhost" || u.hostname === "127.0.0.1" || u.hostname === "::1"; } catch { return false; } })();
  const pool = new Pool({
    connectionString: normalizePgUrl(connectionString),
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
    ...(isLocalhost ? {} : { ssl: { rejectUnauthorized: false } }),
  });
  const transactionStore = new AsyncLocalStorage<TransactionConnection>();
  let ready: Promise<void> = Promise.resolve();
  if (onInit) {
    ready = onInit(pool).catch((error) => {
      console.error("[LexiLoop] PostgreSQL migrations failed:", error);
      throw error;
    });
  }

  const query = async (sql: string, params: unknown[] = []) => {
    await ready;
    const connection = transactionStore.getStore();
    if (connection) return connection.client.query(sql, params);
    return pool.query(sql, params);
  };

  const prepare = (sql: string): PreparedStatement => {
    const rewritten = rewriteSql(sql);
    const isInsert = /^\s*INSERT\b/i.test(sql);
    const hasReturning = /\bRETURNING\b/i.test(rewritten);
    const runSql =
      isInsert && !hasReturning ? `${rewritten.replace(/;\s*$/, "")} RETURNING *` : rewritten;
    return {
      get: async (...params) => (await query(rewritten, params)).rows[0],
      all: async (...params) => (await query(rewritten, params)).rows,
      run: async (...params) => {
        const result = await query(runSql, params);
        return {
          changes: result.rowCount ?? 0,
          lastInsertRowid: toNumber(result.rows[0]?.id),
        };
      },
    };
  };

  const transaction = <TArgs extends unknown[], TResult>(
    fn: (...args: TArgs) => TResult | Promise<TResult>,
  ): SqliteLikeTransaction<TArgs, TResult> => {
    const run = async (args: TArgs): Promise<TResult> => {
      const existing = transactionStore.getStore();
      if (existing) return (await fn(...args)) as TResult;
      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        const result = await transactionStore.run({ client }, () => fn(...args));
        await client.query("COMMIT");
        return result as TResult;
      } catch (error) {
        try {
          await client.query("ROLLBACK");
        } catch {
          // connection-level failure; nothing left to roll back
        }
        throw error;
      } finally {
        client.release();
      }
    };
    const wrapper = ((...args: TArgs) => run(args)) as SqliteLikeTransaction<TArgs, TResult>;
    wrapper.immediate = (...args: TArgs) => run(args);
    wrapper.deferred = (...args: TArgs) => run(args);
    wrapper.exclusive = (...args: TArgs) => run(args);
    return wrapper;
  };

  return {
    mode: "postgres",
    prepare,
    exec: async (sql) => {
      if (/^\s*PRAGMA\b/i.test(sql)) return;
      await query(sql);
    },
    pragma: async () => undefined,
    transaction,
    close: async () => pool.end(),
    backup: async () => {
      throw new Error("SQLite file backup is unavailable — use JSON backup (GET /api/backups/json, POST /api/backups/restore) on PostgreSQL.");
    },
  };
}
