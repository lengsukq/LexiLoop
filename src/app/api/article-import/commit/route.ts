import { NextRequest } from "next/server";
import { handleRouteError, ok } from "@/lib/api";
import { IMPORT_MODES } from "@/lib/types";
import { MAX_ARTICLE_SELECTED } from "@/lib/config";
import { ApiError } from "@/lib/api";
import { sqlite } from "@/db/client";
import { runBackgroundTick } from "@/modules/background/tick";
import { commitImport } from "@/modules/imports/service";
import { z } from "zod";

const selectedTermSchema = z.union([
  z.string().trim().min(1).max(600),
  z.object({ term: z.string().trim().min(1).max(600), entryType: z.enum(["WORD","PHRASE","SENTENCE"]).optional() }),
]);
const schema = z.object({
  previewToken: z.string().uuid(),
  selectedTerms: z.array(selectedTermSchema).max(MAX_ARTICLE_SELECTED).optional(),
  selectedKeys: z.array(z.string().trim().min(1).max(700)).max(MAX_ARTICLE_SELECTED).optional(),
  mode: z.enum(IMPORT_MODES),
  resetLearningProgress: z.boolean().default(false),
});

export const maxDuration = 120;

function toKey(term: string, entryType?: string) {
  const normalized = term.normalize("NFKC").toLowerCase();
  if (entryType) return `${entryType}\u0000${normalized}`;
  return normalized;
}

export async function POST(request: NextRequest) {
  try {
    const input = schema.parse(await request.json());

    const keys: string[] | null = (() => {
      if (input.selectedKeys?.length) return input.selectedKeys.map((k) => k.normalize("NFKC").toLowerCase());
      if (!input.selectedTerms?.length) return null;
      return input.selectedTerms.map((v) => {
        if (typeof v === "string") return toKey(v);
        return toKey(v.term, v.entryType);
      });
    })();

    if (keys && keys.length > 0) {
      const hasComposite = keys.some((k) => k.includes("\u0000"));
      const keySet = new Set(keys);
      const termOnlySet = new Set(keys.map((k) => k.split("\u0000").pop()!));
      const preview = await sqlite.prepare("SELECT rows_json FROM import_previews WHERE token = ? LIMIT 1").get(input.previewToken) as
        | { rows_json: string }
        | undefined;
      if (preview) {
        try {
          const rows = JSON.parse(preview.rows_json) as Array<{ normalizedTerm: string; entryType?: string; sourceLanguage?: string; targetLanguage?: string; sourceLanguageName?: string; targetLanguageName?: string; term?: string }>;
          const filtered = rows.filter((row) => {
            const normalized = row.normalizedTerm.normalize("NFKC").toLowerCase();
            const etLower = (row.entryType ?? "WORD").toLowerCase();
            const composite = `${etLower}\u0000${normalized}`;
            if (hasComposite) return keySet.has(composite) || keySet.has(normalized);
            return termOnlySet.has(normalized);
          });
          if (filtered.length > 0) {
            await sqlite.prepare("UPDATE import_previews SET rows_json = ? WHERE token = ?").run(JSON.stringify(filtered), input.previewToken);
          } else {
            // 宽松回退：即使不在预览也直接初始化（临时预览），避免前端已选 24 个却被拦截
            console.warn("[article-import] selectedKeys 未命中预览，回退为临时行直接导入", { selected: keys.length, previewRows: rows.length });
            const firstRow = rows[0] as unknown as { sourceLanguage?: string; targetLanguage?: string; sourceLanguageName?: string; targetLanguageName?: string } | undefined;
            const fallbackSourceLanguage = firstRow?.sourceLanguage ?? "en";
            const fallbackTargetLanguage = firstRow?.targetLanguage ?? "zh-CN";
            const fallbackSourceName = firstRow?.sourceLanguageName ?? "英语";
            const fallbackTargetName = firstRow?.targetLanguageName ?? "简体中文";
            // 尝试用预览中的原始大小写还原 term，找不到则用 normalized
            const termByKey = new Map<string, string>();
            for (const r of rows) {
              const n = (r.normalizedTerm as string).normalize("NFKC").toLowerCase();
              const etL = (r.entryType ?? "WORD").toLowerCase();
              termByKey.set(`${etL}\u0000${n}`, (r.term as string) ?? (r.normalizedTerm as string));
              if (!termByKey.has(n)) termByKey.set(n, (r.term as string) ?? (r.normalizedTerm as string));
            }
            const syntheticRows = keys.map((k, idx) => {
              const hasSep = k.includes("\u0000");
              const [etPart, termPartRaw] = hasSep ? (k.split("\u0000") as [string, string]) : ["word", k];
              const entryType = etPart.toUpperCase() === "PHRASE" ? "PHRASE" : etPart.toUpperCase() === "SENTENCE" ? "SENTENCE" : "WORD";
              const normalizedTerm = termPartRaw ?? k;
              const term = termByKey.get(k) ?? termByKey.get(normalizedTerm) ?? normalizedTerm;
              return {
                rowNumber: idx + 1,
                term,
                normalizedTerm,
                sourceLanguage: fallbackSourceLanguage,
                targetLanguage: fallbackTargetLanguage,
                sourceLanguageName: fallbackSourceName,
                targetLanguageName: fallbackTargetName,
                entryType,
                sourceCreatedAt: null,
                status: "NEW" as const,
                errors: [] as string[],
                _article: { occurrences: 1, aiReason: null, difficulty: null, cefrLevel: null, frequency: null, entryType, sourceSentence: null, aiCard: null },
              };
            });
            await sqlite.prepare("UPDATE import_previews SET rows_json = ? WHERE token = ?").run(JSON.stringify(syntheticRows), input.previewToken);
          }
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
