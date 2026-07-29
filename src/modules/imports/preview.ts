import crypto from "node:crypto";
import { db } from "@/db/client";
import { importPreviews, words } from "@/db/schema";
import { IMPORT_PREVIEW_TTL_MS } from "@/lib/config";
import { mapLanguage } from "@/lib/language";
import type { ImportPreview, ImportPreviewRow } from "@/lib/types";
import { and, eq, lt, sql } from "drizzle-orm";
import { parseEasyDictCsv } from "./parser";
import { detectEntryType, identityKey, normalizeTerm } from "./normalizer";

export async function createImportPreview(content: string, filename: string): Promise<ImportPreview> {
  const parsed = parseEasyDictCsv(content);
  if (parsed.parseErrors.length > 0 && parsed.rows.length === 0) throw new Error(parsed.parseErrors.join("；"));
  await db.delete(importPreviews).where(lt(importPreviews.expiresAt, new Date()));
  const existingRows = await db.select({ normalizedTerm: words.normalizedTerm, sourceLanguage: words.sourceLanguage, targetLanguage: words.targetLanguage }).from(words);
  const existing = new Set(existingRows.map((row) => identityKey(row.normalizedTerm, row.sourceLanguage, row.targetLanguage)));
  const seen = new Set<string>();
  const rows: ImportPreviewRow[] = parsed.rows.map((row) => {
    if (!row.data) return {
      rowNumber: row.rowNumber, term: row.raw.queryText ?? "", normalizedTerm: "", sourceLanguage: "und", targetLanguage: "und",
      sourceLanguageName: row.raw.queryFromLanguage ?? "", targetLanguageName: row.raw.queryToLanguage ?? "", entryType: "WORD",
      sourceCreatedAt: null, status: "INVALID", errors: row.errors,
    };
    const source = mapLanguage(row.data.queryFromLanguage);
    const target = mapLanguage(row.data.queryToLanguage);
    const normalizedTerm = normalizeTerm(row.data.queryText, source.code);
    const key = identityKey(normalizedTerm, source.code, target.code);
    const duplicate = seen.has(key);
    seen.add(key);
    return {
      rowNumber: row.rowNumber, term: row.data.queryText, normalizedTerm, sourceLanguage: source.code, targetLanguage: target.code,
      sourceLanguageName: source.name, targetLanguageName: target.name, entryType: detectEntryType(row.data.queryText),
      sourceCreatedAt: row.data.timestamp ? new Date(row.data.timestamp).toISOString() : null,
      status: duplicate ? "DUPLICATE" : existing.has(key) ? "EXISTING" : "NEW",
      errors: duplicate ? ["CSV 内重复词条，提交时仅处理第一次出现的记录。"] : [],
    };
  });
  const token = crypto.randomUUID();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + IMPORT_PREVIEW_TTL_MS);
  await db.insert(importPreviews).values({ token, filename, fileHash: crypto.createHash("sha256").update(content).digest("hex"), rowsJson: rows, expiresAt, createdAt: now });
  const valid = rows.filter((row) => row.status !== "INVALID" && row.status !== "DUPLICATE");
  const languages: Record<string, number> = {};
  const entryTypes: Record<string, number> = {};
  for (const row of valid) {
    languages[row.sourceLanguage] = (languages[row.sourceLanguage] ?? 0) + 1;
    entryTypes[row.entryType] = (entryTypes[row.entryType] ?? 0) + 1;
  }
  return {
    previewToken: token, filename, totalRows: rows.length, validRows: valid.length,
    invalidRows: rows.filter((row) => row.status === "INVALID").length,
    duplicateRows: rows.filter((row) => row.status === "DUPLICATE").length,
    newRows: rows.filter((row) => row.status === "NEW").length,
    existingRows: rows.filter((row) => row.status === "EXISTING").length,
    languages, entryTypes, rows, expiresAt: expiresAt.toISOString(),
  };
}

export async function getImportPreview(token: string) {
  const rows = await db.select().from(importPreviews)
    .where(and(eq(importPreviews.token, token), sql`${importPreviews.expiresAt} > ${new Date()}`)).limit(1);
  return rows[0] ?? null;
}
