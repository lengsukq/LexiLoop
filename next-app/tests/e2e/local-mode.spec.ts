import { expect, test } from "@playwright/test";

test("passwordless browser local mode loads PGlite WASM, persists across reloads, exports JSON, and isolates cloud DB", async ({ page }) => {
  const pageErrors: string[] = [];
  const consoleErrors: string[] = [];
  const assetFailures: string[] = [];

  page.on("pageerror", (error) => {
    pageErrors.push(error.message);
  });
  page.on("console", (msg) => {
    if (msg.type() === "error") {
      // Exclude our intentional fetch('/api/words') 401 probe below.
      const text = msg.text();
      if (!text.includes("401")) consoleErrors.push(text);
    }
  });
  page.on("response", (response) => {
    const url = response.url();
    if (response.status() >= 400 && (url.includes(".wasm") || url.includes(".data") || url.includes("/_next/static/"))) {
      assetFailures.push(`${response.status()} ${url}`);
    }
  });

  await page.goto("/");

  if (process.env.EXPECT_PASSWORD_GATE === "1") {
    await expect(page).toHaveURL(/\/login/);
    const unauthWordsStatus = await page.evaluate(async () => {
      const res = await fetch("/api/words", { cache: "no-store" });
      return res.status;
    });
    expect(unauthWordsStatus).toBe(401);
  }

  if (new URL(page.url()).pathname === "/login") {
    await page.getByRole("button", { name: "无需密码 · 使用浏览器本地模式" }).click();
    await expect(page).toHaveURL(/\/$/);
  } else {
    await page.goto("/settings?tab=data");
    await page.getByRole("button", { name: "切换到浏览器本地模式（免密）" }).click();
  }

  // Confirm sidebar indicates Local Browser Mode.
  await expect(page.getByText("浏览器本地模式").first()).toBeVisible({ timeout: 30_000 });

  // Cloud DB APIs remain strictly blocked even while lexiloop_mode=local is active.
  if (process.env.EXPECT_PASSWORD_GATE === "1") {
    const localCookieCloudWordsStatus = await page.evaluate(async () => {
      const res = await fetch("/api/words", { cache: "no-store" });
      return res.status;
    });
    expect(localCookieCloudWordsStatus).toBe(401);
  }

  // Edit and persist a setting into browser IndexedDB (PGlite WASM).
  await page.goto("/settings");
  const dailyNewWordsInput = page.locator("label", { hasText: "每日新词" }).locator("input");
  await expect(dailyNewWordsInput).toBeVisible({ timeout: 30_000 });
  await dailyNewWordsInput.fill("33");
  await page.getByRole("button", { name: "保存" }).click();
  await expect(page.getByText("学习设置已保存").first()).toBeVisible({ timeout: 15_000 });

  // Import a CSV word into Browser PGlite.
  await page.goto("/import");
  const fileInput = page.locator('input[type="file"][accept*=".csv"]');
  await expect(fileInput).toBeAttached();
  await fileInput.setInputFiles({
    name: "browser-local.csv",
    mimeType: "text/csv",
    buffer: Buffer.from(
      "queryText,queryFromLanguage,queryToLanguage,timestamp\n"
      + "serendipity,English,Chinese-Simplified,2026-03-01T00:00:00Z\n",
    ),
  });
  await expect(page.getByRole("button", { name: "确认导入" })).toBeEnabled({ timeout: 15_000 });
  await page.getByRole("button", { name: "确认导入" }).click();
  await expect(page.getByText("导入完成").first()).toBeVisible({ timeout: 20_000 });

  // Reload browser page: skip /login automatically and preserve IndexedDB data.
  await page.reload();
  await expect(page).not.toHaveURL(/\/login/);

  await page.goto("/words");
  await expect(page.getByText("serendipity").first()).toBeVisible({ timeout: 30_000 });

  await page.goto("/settings");
  const reloadedInput = page.locator("label", { hasText: "每日新词" }).locator("input");
  await expect(reloadedInput).toHaveValue("33", { timeout: 30_000 });

  // Verify JSON backup download comes from local PGlite cleanly.
  await page.getByRole("button", { name: "数据管理" }).click();
  await expect(page.getByText("浏览器本地模式（免密）").first()).toBeVisible();

  const downloadPromise = page.waitForEvent("download");
  await page.getByRole("button", { name: "下载 JSON 备份" }).click();
  const download = await downloadPromise;
  expect(download.suggestedFilename()).toMatch(/^lexiloop-local-\d{4}-\d{2}-\d{2}\.json$/);
  const stream = await download.createReadStream();
  const chunks: Buffer[] = [];
  for await (const chunk of stream) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const backup = JSON.parse(Buffer.concat(chunks).toString("utf8")) as {
    format: string;
    words: Array<{ term: string }>;
    settings: Array<{ key: string; value_json: string }>;
  };
  expect(backup.format).toBe("lexiloop-json-backup");
  expect(backup.words.some((w) => w.term === "serendipity")).toBe(true);
  expect(backup.settings.some((s) => s.key === "dailyNewWords" && JSON.parse(s.value_json) === 33)).toBe(true);

  // Switch back to Cloud mode -> returns to /login when password protection is enabled.
  if (process.env.EXPECT_PASSWORD_GATE === "1") {
    await page.getByRole("button", { name: "切换到云端数据库模式（登录）" }).click();
    await expect(page).toHaveURL(/\/login/);
  }

  expect(assetFailures).toEqual([]);
  expect(pageErrors).toEqual([]);
  expect(consoleErrors).toEqual([]);
});
