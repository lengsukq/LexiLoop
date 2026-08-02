import { PG_INITIAL_SQL } from "./0000_pg_initial";
import { PG_POSITION_FLOAT_SQL } from "./0001_position_float";

export interface PgMigration {
  name: string;
  sql: string;
}

export const PG_MIGRATIONS: readonly PgMigration[] = [
  { name: "0000_pg_initial.sql", sql: PG_INITIAL_SQL },
  { name: "0001_position_float.sql", sql: PG_POSITION_FLOAT_SQL },
];
