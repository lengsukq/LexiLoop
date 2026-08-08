import { sqlite } from "@/db/client";
import crypto from "node:crypto";
import { IMPORT_PREVIEW_TTL_MS } from "@/lib/config";
import { mapLanguage } from "@/lib/language";
import { ENTRY_TYPES, type EntryType, type ManualContentPreview, type ProviderAttempt } from "@/lib/types";
import { contentStatus, dictionaryContentFromRow, mergeDictionaryContent, normalizeDictionaryContent } from "@/modules/dictionary/content";
import { lookupDictionary } from "@/modules/dictionary/pipeline";
import { detectEntryType, displayTerm, legacyEntryType, normalizeTerm } from "@/modules/imports/normalizer";
import { getSettings } from "@/modules/settings/service";
import { z } from "zod";
import { fieldsReturned, rowToPreview, saveAttempts, saveContent } from "./storage";

const previewInputSchema = z.object({
  text: z.string().trim().min(1).max(1200),
  sourceLanguage: z.string().trim().min(1).max(50).default("en"),
  targetLanguage: z.string().trim().min(1).max(50).default("zh-CN"),
  contentType: z.enum(ENTRY_TYPES).optional(),
}).strict();

const confirmInputSchema = z.object({ previewToken: z.string().uuid() }).strict();

export class ManualPreviewError extends Error {
  constructor(public readonly code: string, message: string, public readonly details?: unknown) {
    super(message);
    this.name = "ManualPreviewError";
  }
}

export async function createManualPreview(input: unknown): Promise<ManualContentPreview> {
  const values = previewInputSchema.parse(input);
  const source = mapLanguage(values.sourceLanguage);
  const target = mapLanguage(values.targetLanguage);
  const contentType = values.contentType ?? detectEntryType(values.text);
  const normalizedTerm = normalizeTerm(values.text, source.code);
  const settings = await getSettings();
  const existing = await sqlite.prepare(`SELECT id FROM words
    WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1`)
    .get(normalizedTerm, source.code, target.code) as { id: number } | undefined;

  const result = await lookupDictionary({
    term: values.text,
    normalizedTerm,
    entryType: contentType,
    sourceLanguage: source.code,
    targetLanguage: target.code,
    initializationMode: "FORCE_OVERWRITE",
    requestedProviders: ["youdao"],
  }, settings);
  if (result.requiredProviderFailure) {
    throw new ManualPreviewError(
      result.requiredProviderFailure.errorCode,
      result.requiredProviderFailure.errorMessage,
    );
  }
  const content = normalizeDictionaryContent(result.content);
  if (contentStatus(content, contentType) === "FAILED") {
    throw new ManualPreviewError("DICTIONARY_PREVIEW_EMPTY", "词典没有返回可用释义，请调整输入或稍后重试。");
  }
  const attempts = result.attempts.map((attempt) => ({
    ...attempt,
    fieldsReturned: attempt.fieldsReturned.length ? attempt.fieldsReturned : fieldsReturned(content),
  }));
  const token = crypto.randomUUID();
  const now = Date.now();
  const expiresAt = now + IMPORT_PREVIEW_TTL_MS;
  await sqlite.transaction(async () => {
    await sqlite.prepare("UPDATE manual_previews SET status = 'EXPIRED' WHERE status = 'PREVIEW' AND expires_at < ?").run(now);
    await sqlite.prepare(`INSERT INTO manual_previews
      (token, input_text, normalized_term, source_language, target_language, source_language_name,
       target_language_name, content_type, content_json, provider_attempts_json, existing_word_id,
       status, expires_at, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'PREVIEW', ?, ?)`)
      .run(
        token, values.text, normalizedTerm, source.code, target.code, source.name, target.name,
        contentType, JSON.stringify(content), JSON.stringify(attempts), existing?.id ?? null, expiresAt, now,
      );
  }).immediate();

  return {
    previewToken: token,
    term: values.text,
    normalizedTerm,
    sourceLanguage: source.code,
    targetLanguage: target.code,
    sourceLanguageName: source.name,
    targetLanguageName: target.name,
    contentType,
    content,
    providerAttempts: attempts,
    existingWordId: existing?.id ?? null,
    expiresAt: new Date(expiresAt).toISOString(),
  };
}

export async function confirmManualPreview(input: unknown) {
  const { previewToken } = confirmInputSchema.parse(input);
  const now = Date.now();
  return await sqlite.transaction(async () => {
    const row = await sqlite.prepare("SELECT * FROM manual_previews WHERE token = ?").get(previewToken) as {
      token: string; input_text: string; normalized_term: string; source_language: string; target_language: string;
      source_language_name: string | null; target_language_name: string | null; content_type: EntryType;
      content_json: string; provider_attempts_json: string; existing_word_id: number | null; status: string;
      expires_at: number;
    } | undefined;
    if (!row) throw new ManualPreviewError("MANUAL_PREVIEW_NOT_FOUND", "预览不存在，请重新生成。");
    if (row.status === "COMMITTED") {
      const committedWordId = row.existing_word_id;
      if (!committedWordId) throw new ManualPreviewError("MANUAL_PREVIEW_ALREADY_USED", "该预览已经确认。");
      return { wordId: committedWordId, created: false, idempotent: true };
    }
    if (row.status !== "PREVIEW" || row.expires_at < now) {
      await sqlite.prepare("UPDATE manual_previews SET status = 'EXPIRED' WHERE token = ?").run(previewToken);
      throw new ManualPreviewError("MANUAL_PREVIEW_EXPIRED", "预览已过期，请重新生成。", { expiresAt: new Date(row.expires_at).toISOString() });
    }
    const claimed = await sqlite.prepare(`UPDATE manual_previews SET status = 'COMMITTED', committed_at = ?
      WHERE token = ? AND status = 'PREVIEW' AND expires_at >= ?`).run(now, previewToken, now);
    if (claimed.changes !== 1) throw new ManualPreviewError("MANUAL_PREVIEW_ALREADY_USED", "该预览已被其他请求确认。");

    const previewContent = normalizeDictionaryContent(JSON.parse(row.content_json) as Record<string, unknown>);
    const attempts = JSON.parse(row.provider_attempts_json) as ProviderAttempt[];
    let word = await sqlite.prepare(`SELECT id, initialization_status FROM words
      WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1`)
      .get(row.normalized_term, row.source_language, row.target_language) as { id: number; initialization_status: string } | undefined;
    let created = false;
    if (!word) {
      const status = contentStatus(previewContent, row.content_type);
      const inserted = await sqlite.prepare(`INSERT INTO words
        (term, normalized_term, source_language, target_language, source_language_name, target_language_name,
         entry_type, content_type, initialization_status, mastery_level, mastery_score, is_suspended,
         source_created_at, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'NEW', 0, 0, ?, ?, ?)`)
        .run(
          displayTerm(row.input_text, row.source_language, row.content_type), row.normalized_term, row.source_language, row.target_language,
          row.source_language_name, row.target_language_name, legacyEntryType(row.content_type), row.content_type,
          status, now, now, now,
        );
      word = { id: Number(inserted.lastInsertRowid), initialization_status: status };
      created = true;
    }

    const existingRow = await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(word.id) as Record<string, unknown> | undefined;
    const finalContent = existingRow
      ? mergeDictionaryContent(dictionaryContentFromRow(existingRow), previewContent)
      : previewContent;
    const finalStatus = contentStatus(finalContent, row.content_type);
    await saveContent(word.id, finalContent, attempts, now);
    await saveAttempts(word.id, attempts, now);
    await sqlite.prepare("UPDATE words SET content_type = ?, initialization_status = ?, updated_at = ? WHERE id = ?")
      .run(row.content_type, finalStatus, now, word.id);
    await sqlite.prepare(`UPDATE initialization_jobs SET status = 'DISABLED', completed_at = ?, updated_at = ?,
      locked_at = NULL, locked_by = NULL, last_error = 'Manual preview confirmed', last_error_code = 'MANUAL_PREVIEW_CONFIRMED'
      WHERE word_id = ? AND status = 'QUEUED'`).run(now, now, word.id);
    await sqlite.prepare("UPDATE manual_previews SET existing_word_id = ? WHERE token = ?").run(word.id, previewToken);
    return {
      wordId: word.id,
      created,
      idempotent: false,
      initializationStatus: finalStatus,
      contentType: row.content_type,
    };
  }).immediate();
}

export async function getManualPreview(token: string): Promise<ManualContentPreview | null> {
  const now = Date.now();
  const row = await sqlite.prepare(`SELECT * FROM manual_previews
    WHERE token = ? AND status = 'PREVIEW' AND expires_at >= ?`).get(token, now) as Parameters<typeof rowToPreview>[0] | undefined;
  return row ? rowToPreview(row) : null;
}
