import { beforeEach, describe, expect, it } from "vitest";
import { getSettings, invalidateSettingsCache, updateSettings } from "@/modules/settings/service";

describe("choice reveal delay setting", () => {
  beforeEach(() => invalidateSettingsCache());

  it("defaults to two seconds", async () => {
    await expect(getSettings()).resolves.toMatchObject({ choiceRevealDelaySeconds: 2 });
  });

  it("allows immediate reveal and rejects negative values", async () => {
    await expect(updateSettings({ choiceRevealDelaySeconds: 0 })).resolves.toMatchObject({ choiceRevealDelaySeconds: 0 });
    await expect(updateSettings({ choiceRevealDelaySeconds: -1 })).rejects.toThrow();
  });
});
