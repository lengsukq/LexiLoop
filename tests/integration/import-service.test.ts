import fs from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";
import { createImportPreview, commitImport } from "@/modules/imports/service";
import { sqlite } from "@/db/client";

describe("import service", () => {
  it("persists preview, ignores in-file duplicates and queues initialization", async () => {
    const content = fs.readFileSync(path.join(process.cwd(), "tests/fixtures/easydict-sample.csv"), "utf8");
    const preview = await createImportPreview(content, "sample.csv");
    expect(preview.totalRows).toBe(4);
    expect(preview.newRows).toBe(3);
    expect(preview.duplicateRows).toBe(1);
    const result = await commitImport(preview.previewToken, "FILL_MISSING", false);
    expect(result.createdWords).toBe(3);
    expect(result.queuedInitializations).toBe(3);
    expect((await sqlite.prepare("SELECT count(*) AS count FROM words").get() as { count: number }).count).toBe(3);
    await expect(commitImport(preview.previewToken, "FILL_MISSING", false)).rejects.toMatchObject({ code: "IMPORT_PREVIEW_EXPIRED" });
  });

  it("upgrades existing active jobs for fill-missing imports", async () => {
    const content = fs.readFileSync(path.join(process.cwd(), "tests/fixtures/easydict-sample.csv"), "utf8");
    const first = await createImportPreview(content, "first.csv");
    await commitImport(first.previewToken, "SKIP_EXISTING", false);
    const second = await createImportPreview(content, "second.csv");
    expect(second.existingRows).toBe(3);
    await commitImport(second.previewToken, "FILL_MISSING", false);
    const modes = await sqlite.prepare("SELECT DISTINCT mode FROM initialization_jobs").all() as Array<{ mode: string }>;
    expect(modes).toEqual([{ mode: "FILL_MISSING_FIELDS" }]);
  });
});
