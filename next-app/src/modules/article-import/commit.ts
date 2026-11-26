import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api-errors";
import { articleCommitSchema } from "@/lib/route-schemas";
import { runBackgroundTick } from "@/modules/background/tick";
import { commitImport } from "@/modules/imports/service";

function toKey(term: string, entryType?: string) {
  const normalized = term.normalize("NFKC").toLowerCase();
  if (entryType) return `${entryType}\u0000${normalized}`;
  return normalized;
}

export async function commitArticleImport(rawInput: unknown) {
  const input = articleCommitSchema.parse(rawInput);

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
        const rows = JSON.parse(preview.rows_json) as Array<{
          normalizedTerm: string;
          entryType?: string;
          sourceLanguage?: string;
          targetLanguage?: string;
          sourceLanguageName?: string;
          targetLanguageName?: string;
          term?: string;
        }>;
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
          console.warn("[article-import] selectedKeys 未命中预览，回退为临时行直接导入", { selected: keys.length, previewRows: rows.length });
          const firstRow = rows[0];
          const fallbackSourceLanguage = firstRow?.sourceLanguage ?? "en";
          const fallbackTargetLanguage = firstRow?.targetLanguage ?? "zh-CN";
          const fallbackSourceName = firstRow?.sourceLanguageName ?? "英语";
          const fallbackTargetName = firstRow?.targetLanguageName ?? "简体中文";
          const termByKey = new Map<string, string>();
          for (const r of rows) {
            const n = r.normalizedTerm.normalize("NFKC").toLowerCase();
            const etL = (r.entryType ?? "WORD").toLowerCase();
            termByKey.set(`${etL}\u0000${n}`, r.term ?? r.normalizedTerm);
            if (!termByKey.has(n)) termByKey.set(n, r.term ?? r.normalizedTerm);
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
  return result;
}
