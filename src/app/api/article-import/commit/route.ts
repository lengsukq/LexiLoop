import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { IMPORT_MODES } from "@/lib/types";
import { MAX_ARTICLE_SELECTED } from "@/lib/config";
import { ApiError } from "@/lib/api";
import { sqlite } from "@/db/client";
import { runBackgroundTick } from "@/modules/background/tick";
import { commitImport } from "@/modules/imports/service";
import { z } from "zod";

const schema = z.object({
  previewToken: z.string().uuid(),
  selectedTerms: z.array(z.string().trim().min(1).max(80)).max(MAX_ARTICLE_SELECTED).optional(),
  mode: z.enum(IMPORT_MODES),
  resetLearningProgress: z.boolean().default(false),
});

export const maxDuration = 60;

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());

    if (input.selectedTerms && input.selectedTerms.length > 0) {
      const normalizedSelected = new Set(input.selectedTerms.map((term) => term.normalize("NFKC").toLowerCase()));
      const preview = await sqlite.prepare("SELECT rows_json FROM import_previews WHERE token = ? LIMIT 1").get(input.previewToken) as
        | { rows_json: string }
        | undefined;
      if (preview) {
        try {
          const rows = JSON.parse(preview.rows_json) as Array<{ normalizedTerm: string }>;
          const filtered = rows.filter((row) => normalizedSelected.has(row.normalizedTerm.toLowerCase()));
          if (filtered.length === 0) throw new ApiError("VALIDATION_ERROR", "选中的词条不在预览范围内。");
          await sqlite.prepare("UPDATE import_previews SET rows_json = ? WHERE token = ?").run(JSON.stringify(filtered), input.previewToken);
        } catch (error) {
          if (error instanceof ApiError) throw error;
        }
      }
    }

    const result = await commitImport(input.previewToken, input.mode, input.resetLearningProgress);
    try {
      await runBackgroundTick({ maxJobs: 3 });
    } catch (tickError) {
      console.error("[BackgroundTick] on-demand tick after article import commit failed", tickError);
    }
    return ok(result);
  } catch (error) {
    return handleRouteError(error, { validationMessage: "提交参数无效。", fallbackMessage: "提交文章导入失败。" });
  }
}
