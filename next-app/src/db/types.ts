export type DatabaseMode = "postgres";

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
 * PostgreSQL facade that preserves the async `prepare().get/all/run` and
 * `transaction()` call sites historically written against better-sqlite3.
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
  /** @deprecated SQLite file backup — PostgreSQL uses JSON backup instead. */
  backup(destination: string): Promise<void>;
}

/**
 * Converts SQLite-style positional `?` placeholders into PostgreSQL `$1, $2, ...`.
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

export function toNumber(value: unknown): number | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value === "bigint") return Number(value);
  if (typeof value === "string") return Number(value);
  return value as number;
}
