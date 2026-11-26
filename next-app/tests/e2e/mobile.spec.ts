import { expect, test } from "@playwright/test";

for (const width of [320, 375, 390]) {
  test(`mobile navigation and filters fit ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 800 });
    await page.goto("/words");

    await expect(page.getByRole("link", { name: "今日" })).toBeVisible();
    await expect(page.getByRole("link", { name: "复习" })).toBeVisible();
    await expect(page.getByRole("link", { name: "单词本" })).toBeVisible();
    await expect(page.getByRole("link", { name: "添加", exact: true })).toBeVisible();
    await expect(page.getByRole("button", { name: "打开更多导航" })).toBeVisible();
    const hasNoHorizontalOverflow = await page.locator("body").evaluate((body) => body.scrollWidth <= window.innerWidth);
    expect(hasNoHorizontalOverflow).toBeTruthy();

    await page.getByRole("button", { name: "打开筛选" }).click();
    await expect(page.getByRole("heading", { name: "筛选单词本" })).toBeVisible();
  });
}

test("mobile review shortcut starts the daily session", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/");
  await page.getByRole("link", { name: "复习" }).click();
  await expect(page).toHaveURL(/\/study/);
});
