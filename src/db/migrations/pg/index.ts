import { PG_INITIAL_SQL } from "./0000_pg_initial";
import { PG_POSITION_FLOAT_SQL } from "./0001_position_float";
import { PG_WORD_REVIEW_STATS_SQL } from "./0001_word_review_stats";
import { PG_NEW_QUESTION_TYPES_SQL } from "./0002_new_question_types";

export interface PgMigration {
  name: string;
  sql: string;
}

export const PG_MIGRATIONS: readonly PgMigration[] = [
  { name: "0000_pg_initial.sql", sql: PG_INITIAL_SQL },
  { name: "0001_position_float.sql", sql: PG_POSITION_FLOAT_SQL },
  { name: "0001_word_review_stats.sql", sql: PG_WORD_REVIEW_STATS_SQL },
  { name: "0002_new_question_types.sql", sql: PG_NEW_QUESTION_TYPES_SQL },
];
