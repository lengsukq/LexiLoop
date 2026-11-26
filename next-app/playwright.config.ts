import { defineConfig, devices } from "@playwright/test";

const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? "http://127.0.0.1:3100";

// E2E tests must never run against the production database; derive a sibling
// test database from DATABASE_URL (e.g. <project>/neondb -> neondb_test).
if (!process.env.PLAYWRIGHT_BASE_URL) {
  const productionUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL =
    process.env.TEST_DATABASE_URL ?? productionUrl?.replace(/\/[^/?]+(\?|$)/, "/neondb_test$1");
}

export default defineConfig({
  testDir: "./tests/e2e",
  fullyParallel: false,
  use: { baseURL, trace: "on-first-retry" },
  webServer: process.env.PLAYWRIGHT_BASE_URL ? undefined : {
    command: "yarn dev --port 3100",
    url: "http://127.0.0.1:3100/api/health",
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
