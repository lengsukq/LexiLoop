import { AsyncLocalStorage } from "node:async_hooks";
import { Pool, types as pgTypes } from "pg";

export type DatabaseMode = "sqlite" | "postgres";

export interface RunResult {
  changes: number;
  lastInsertRowid: number | undefined;
}

export interface PreparedStatement {
  get(...params: unknown[]): Promise<unknown>;
  all(...params: unknown[]): Promise<unknown[]>;
  run(...params: unknown[]): Promise<RunResult>;
}

export type SqliteLikeTransaction<TArgs extends unknown[], TResult> = {
  (...args: TArgs): Promise<TResult>;
  immediate(...args: TArgs): Promise<TResult>;
  deferred(...args: TArgs): Promise<TResult>;
  exclusive(...args: TArgs): Promise<TResult>;
};

/**
 * The facade mirrors the subset of the better-sqlite3 API that LexiLoop uses,
 * but every method is async so a single code path works against both backends.
 */
export interface SqliteLikeDatabase {
  readonly mode: DatabaseMode;
  prepare(sql: string): PreparedStatement;
  exec(sql: string): Promise<void>;
  pragma(source: string, options?: { simple?: boolean }): Promise<unknown>;
  transaction<TArgs extends unknown[], TResult>(
    fn: (...args: TArgs) => TResult | Promise<TResult>,
  ): SqliteLikeTransaction<TArgs, TResult>;
  close(): Promise<void>;
  backup(destination: string): Promise<void>;
}

// ---- placeholder rewriting -------------------------------------------------

/**
 * Converts SQLite positional `?` placeholders into PostgreSQL `$1, $2, ...`.
 * Scans quoted strings and comments so literal question marks are preserved.
 */
export function rewriteSql(sql: string): string {
  let index = 0;
  let output = "";
  let i = 0;
  const length = sql.length;
  while (i < length) {
    const ch = sql[i];
    if (ch === "'" || ch === '"') {
      const quote = ch;
      output += ch;
      i += 1;
      while (i < length) {
        const c = sql[i];
        output += c;
        // NOTE: no backslash-escape handling here. Both PostgreSQL
        // (standard_conforming_strings=on) and SQLite use doubled quotes to
        // escape a quote inside a string literal; backslash is an ordinary
        // character. Treating `\` as an escape here corrupted literals such
        // as `ESCAPE '\'` (rewrote them to `ESCAPE ''`).
        if (c === quote) {
          i += 1;
          break;
        }
        i += 1;
      }
      continue;
    }
    if (ch === "-" && sql[i + 1] === "-") {
      while (i < length && sql[i] !== "\n") {
        output += sql[i];
        i += 1;
      }
      continue;
    }
    if (ch === "/" && sql[i + 1] === "*") {
      output += "/*";
      i += 2;
      while (i < length && !(sql[i] === "*" && sql[i + 1] === "/")) {
        output += sql[i];
        i += 1;
      }
      if (i < length) {
        output += "*/";
        i += 2;
      }
      continue;
    }
    if (ch === "?") {
      index += 1;
      output += `$${index}`;
      i += 1;
      continue;
    }
    output += ch;
    i += 1;
  }
  return output;
}

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

function toNumber(value: unknown): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value === "bigint") return Number(value);
  if (typeof value === "string") return Number(value);
  return value as number;
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

  const pool = new Pool({
    connectionString: normalizePgUrl(connectionString),
    max: 10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 10000,
    ssl: { rejectUnauthorized: false },
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
      throw new Error("SQLite file backup is unavailable in PostgreSQL mode");
    },
  };
}
