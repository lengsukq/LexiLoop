import { migrateDatabase } from "../src/db/migrate";

const databasePath = process.env.DATABASE_PATH ?? "./data/app.sqlite";
migrateDatabase(databasePath);
console.log(`[LexiLoop] migrations applied: ${databasePath}`);
