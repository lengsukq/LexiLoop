import { expect, test } from "@playwright/test";
test("home page and import navigation render", async ({ page }) => {
  await page.goto("/");
  await expect(page).toHaveTitle(/LexiLoop/);
  await expect(page.getByText("LexiLoop", { exact: true }).first()).toBeVisible();
  await page.goto("/import");
  await expect(page.getByRole("heading", { name: "导入 EasyDict CSV" })).toBeVisible();
});
