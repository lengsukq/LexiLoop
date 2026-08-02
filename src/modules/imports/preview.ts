import crypto from "node:crypto";
import { sqlite } from "@/db/client";
import { IMPORT_PREVIEW_TTL_MS } from "@/lib/config";
import { mapLanguage } from "@/lib/language";
import type { ImportPreview, ImportPreviewRow } from "@/lib/types";
import { parseEasyDictCsv } from "./parser";
import { detectEntryType, identityKey, normalizeTerm } from "./normalizer";

export async function createImportPreview(content: string, filename: string): Promise<ImportPreview> {
  const parsed = parseEasyDictCsv(content);
  if (parsed.parseErrors.length > 0 && parsed.rows.length === 0) throw new Error(parsed.parseErrors.join("；"));
  const now = Date.now();
  await sqlite.prepare("DELETE FROM import_previews WHERE expires_at < ?").run(now);
  const existingRows = await sqlite.prepare(
    "SELECT normalized_term, source_language, target_language FROM words",
  ).all() as Array<{ normalized_term: string; source_language: string; target_language: string }>;
  const existing = new Set(existingRows.map((row) => identityKey(row.normalized_term, row.source_language, row.target_language)));
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
  const expiresAt = new Date(now + IMPORT_PREVIEW_TTL_MS);
  await sqlite.prepare(
    "INSERT INTO import_previews(token, filename, file_hash, rows_json, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)",
  ).run(token, filename, crypto.createHash("sha256").update(content).digest("hex"), JSON.stringify(rows), expiresAt.getTime(), now);
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
  const row = await sqlite.prepare(
    "SELECT * FROM import_previews WHERE token = ? AND expires_at > ? LIMIT 1",
  ).get(token, Date.now());
  return (row as { token: string; filename: string; file_hash: string; rows_json: string; expires_at: number; created_at: number } | undefined) ?? null;
}
