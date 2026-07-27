import crypto from "node:crypto";
import { db, sqlite } from "@/db/client";
import { importPreviews, words } from "@/db/schema";
import { IMPORT_PREVIEW_TTL_MS } from "@/lib/config";
import { mapLanguage } from "@/lib/language";
import type { ImportMode, ImportPreview, ImportPreviewRow, InitializationMode } from "@/lib/types";
import { and, eq, lt, sql } from "drizzle-orm";
import { parseEasyDictCsv } from "./parser";
import { detectEntryType, identityKey, legacyEntryType, normalizeTerm } from "./normalizer";

function queueModeForImport(mode: ImportMode, isNew: boolean): InitializationMode | null {
  if (isNew) return "SKIP_INITIALIZED";
  if (mode === "FILL_MISSING") return "FILL_MISSING_FIELDS";
  if (mode === "FORCE_DICTIONARY_REFRESH") return "FORCE_OVERWRITE";
  return null;
}

function strongerMode(current: string, requested: InitializationMode): InitializationMode {
  const weight: Record<string, number> = { SKIP_INITIALIZED: 1, FILL_MISSING_FIELDS: 2, FORCE_OVERWRITE: 3 };
  return (weight[requested] ?? 0) > (weight[current] ?? 0) ? requested : current as InitializationMode;
}

function cancelPendingStudyItemsForWord(wordId: number, now: number): void {
  const sessions = sqlite.prepare(`SELECT study_session_id AS session_id, count(*) AS count
    FROM study_session_items
    WHERE word_id = ? AND status = 'PENDING'
    GROUP BY study_session_id`).all(wordId) as Array<{ session_id: number; count: number }>;
  if (sessions.length === 0) return;
  sqlite.prepare(`UPDATE study_session_items SET status = 'SKIPPED', answered_at = ?, skip_reason = 'PROGRESS_RESET'
    WHERE word_id = ? AND status = 'PENDING'`).run(now, wordId);
  for (const session of sessions) {
    sqlite.prepare(`UPDATE study_sessions SET completed_count = completed_count + ? WHERE id = ?`)
      .run(session.count, session.session_id);
    const pending = sqlite.prepare(`SELECT count(*) AS count FROM study_session_items
      WHERE study_session_id = ? AND status = 'PENDING'`).get(session.session_id) as { count: number };
    if (pending.count === 0) {
      const started = sqlite.prepare("SELECT started_at FROM study_sessions WHERE id = ?").get(session.session_id) as { started_at: number };
      sqlite.prepare("UPDATE study_sessions SET completed_at = ?, duration_ms = ? WHERE id = ?")
        .run(now, now - started.started_at, session.session_id);
    }
  }
}

function markWordInitializationQueued(wordId: number, now: number): void {
  const content = sqlite.prepare("SELECT definitions_json FROM word_contents WHERE word_id = ?").get(wordId) as { definitions_json: string } | undefined;
  let hasDefinition = false;
  if (content) {
    try { hasDefinition = (JSON.parse(content.definitions_json) as unknown[]).length > 0; } catch { hasDefinition = false; }
  }
  if (!hasDefinition) {
    sqlite.prepare("UPDATE words SET initialization_status = 'QUEUED', updated_at = ? WHERE id = ?").run(now, wordId);
  }
}

function enqueueJob(wordId: number, mode: InitializationMode, priority: number, now: number): boolean {
  const active = sqlite.prepare(
    "SELECT id, mode, priority FROM initialization_jobs WHERE word_id = ? AND status IN ('QUEUED','RUNNING') LIMIT 1",
  ).get(wordId) as { id: number; mode: string; priority: number } | undefined;

  if (active) {
    sqlite.prepare(`UPDATE initialization_jobs
      SET mode = ?, priority = ?, available_at = ?, updated_at = ?
      WHERE id = ?`).run(strongerMode(active.mode, mode), Math.max(active.priority, priority), now, now, active.id);
    return false;
  }

  sqlite.prepare(`INSERT INTO initialization_jobs
    (word_id, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
    VALUES (?, ?, 'QUEUED', ?, 0, 5, ?, ?, ?)`).run(wordId, mode, priority, now, now, now);
  return true;
}

export async function createImportPreview(content: string, filename: string): Promise<ImportPreview> {
  const parsed = parseEasyDictCsv(content);
  if (parsed.parseErrors.length > 0 && parsed.rows.length === 0) {
    throw new Error(parsed.parseErrors.join("；"));
  }

  await db.delete(importPreviews).where(lt(importPreviews.expiresAt, new Date()));
  const existingRows = await db.select({
    normalizedTerm: words.normalizedTerm,
    sourceLanguage: words.sourceLanguage,
    targetLanguage: words.targetLanguage,
  }).from(words);
  const existing = new Set(existingRows.map((row) => identityKey(row.normalizedTerm, row.sourceLanguage, row.targetLanguage)));
  const seen = new Set<string>();
  const previewRows: ImportPreviewRow[] = [];

  for (const row of parsed.rows) {
    if (!row.data) {
      previewRows.push({
        rowNumber: row.rowNumber,
        term: row.raw.queryText ?? "",
        normalizedTerm: "",
        sourceLanguage: "und",
        targetLanguage: "und",
        sourceLanguageName: row.raw.queryFromLanguage ?? "",
        targetLanguageName: row.raw.queryToLanguage ?? "",
        entryType: "WORD",
        sourceCreatedAt: null,
        status: "INVALID",
        errors: row.errors,
      });
      continue;
    }

    const source = mapLanguage(row.data.queryFromLanguage);
    const target = mapLanguage(row.data.queryToLanguage);
    const normalizedTerm = normalizeTerm(row.data.queryText, source.code);
    const key = identityKey(normalizedTerm, source.code, target.code);
    const duplicate = seen.has(key);
    seen.add(key);
    previewRows.push({
      rowNumber: row.rowNumber,
      term: row.data.queryText,
      normalizedTerm,
      sourceLanguage: source.code,
      targetLanguage: target.code,
      sourceLanguageName: source.name,
      targetLanguageName: target.name,
      entryType: detectEntryType(row.data.queryText),
      sourceCreatedAt: row.data.timestamp ? new Date(row.data.timestamp).toISOString() : null,
      status: duplicate ? "DUPLICATE" : existing.has(key) ? "EXISTING" : "NEW",
      errors: duplicate ? ["CSV 内重复词条，提交时仅处理第一次出现的记录。"] : [],
    });
  }

  const token = crypto.randomUUID();
  const now = new Date();
  const expiresAt = new Date(now.getTime() + IMPORT_PREVIEW_TTL_MS);
  const fileHash = crypto.createHash("sha256").update(content).digest("hex");
  await db.insert(importPreviews).values({
    token,
    filename,
    fileHash,
    rowsJson: previewRows,
    expiresAt,
    createdAt: now,
  });

  const valid = previewRows.filter((row) => row.status !== "INVALID" && row.status !== "DUPLICATE");
  const languages: Record<string, number> = {};
  const entryTypes: Record<string, number> = {};
  for (const row of valid) {
    languages[row.sourceLanguage] = (languages[row.sourceLanguage] ?? 0) + 1;
    entryTypes[row.entryType] = (entryTypes[row.entryType] ?? 0) + 1;
  }

  return {
    previewToken: token,
    filename,
    totalRows: previewRows.length,
    validRows: valid.length,
    invalidRows: previewRows.filter((row) => row.status === "INVALID").length,
    duplicateRows: previewRows.filter((row) => row.status === "DUPLICATE").length,
    newRows: previewRows.filter((row) => row.status === "NEW").length,
    existingRows: previewRows.filter((row) => row.status === "EXISTING").length,
    languages,
    entryTypes,
    rows: previewRows,
    expiresAt: expiresAt.toISOString(),
  };
}

export function commitImport(previewToken: string, mode: ImportMode, resetLearningProgress: boolean) {
  const now = Date.now();
  return sqlite.transaction(() => {
    const preview = sqlite.prepare("SELECT * FROM import_previews WHERE token = ?").get(previewToken) as {
      token: string; filename: string; file_hash: string; rows_json: string; expires_at: number;
    } | undefined;
    if (!preview || preview.expires_at < now) throw new Error("IMPORT_PREVIEW_EXPIRED");

    const claimed = sqlite.prepare("DELETE FROM import_previews WHERE token = ?").run(previewToken);
    if (claimed.changes !== 1) throw new Error("IMPORT_PREVIEW_EXPIRED");
    const rows = JSON.parse(preview.rows_json) as ImportPreviewRow[];

    const batch = sqlite.prepare(`INSERT INTO import_batches
      (filename, file_hash, import_mode, reset_learning_progress, total_rows, valid_rows, invalid_rows, duplicate_rows, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?)`)
      .run(
        preview.filename,
        preview.file_hash,
        mode,
        resetLearningProgress ? 1 : 0,
        rows.length,
        rows.filter((row) => row.status === "NEW" || row.status === "EXISTING").length,
        rows.filter((row) => row.status === "INVALID").length,
        rows.filter((row) => row.status === "DUPLICATE").length,
        now,
      );
    const batchId = Number(batch.lastInsertRowid);
    let createdWords = 0;
    let existingWords = 0;
    let queuedInitializations = 0;

    for (const row of rows) {
      if (row.status === "INVALID" || row.status === "DUPLICATE") {
        sqlite.prepare(`INSERT INTO import_rows
          (import_batch_id, row_number, raw_json, normalized_term, status, error_code, error_message, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
          .run(batchId, row.rowNumber, JSON.stringify(row), row.normalizedTerm || null, row.status, row.status, row.errors.join("；"), now);
        continue;
      }

      const existing = sqlite.prepare(`SELECT id FROM words
        WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1`)
        .get(row.normalizedTerm, row.sourceLanguage, row.targetLanguage) as { id: number } | undefined;
      let wordId: number;
      let isNew = false;

      if (existing) {
        wordId = existing.id;
        existingWords += 1;
      } else {
        const inserted = sqlite.prepare(`INSERT INTO words
          (term, normalized_term, source_language, target_language, source_language_name, target_language_name,
           entry_type, content_type, source_created_at, initialization_status, mastery_level, mastery_score, is_suspended, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', 'NEW', 0, 0, ?, ?)`)
          .run(
            row.term, row.normalizedTerm, row.sourceLanguage, row.targetLanguage,
            row.sourceLanguageName, row.targetLanguageName, legacyEntryType(row.entryType), row.entryType,
            row.sourceCreatedAt ? new Date(row.sourceCreatedAt).getTime() : null,
            now, now,
          );
        wordId = Number(inserted.lastInsertRowid);
        createdWords += 1;
        isNew = true;
      }

      if (resetLearningProgress && !isNew) {
        cancelPendingStudyItemsForWord(wordId, now);
        sqlite.prepare("DELETE FROM review_logs WHERE word_id = ?").run(wordId);
        sqlite.prepare("DELETE FROM review_cards WHERE word_id = ?").run(wordId);
        sqlite.prepare("DELETE FROM wrong_word_states WHERE word_id = ?").run(wordId);
        sqlite.prepare("UPDATE words SET mastery_level = 'NEW', mastery_score = 0, updated_at = ? WHERE id = ?").run(now, wordId);
      }

      const queueMode = queueModeForImport(mode, isNew);
      if (queueMode) {
        const inserted = enqueueJob(wordId, queueMode, isNew ? 10 : mode === "FORCE_DICTIONARY_REFRESH" ? 60 : 30, now);
        if (inserted) queuedInitializations += 1;
        markWordInitializationQueued(wordId, now);
      }

      sqlite.prepare(`INSERT INTO import_rows
        (import_batch_id, row_number, raw_json, normalized_term, word_id, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)`)
        .run(batchId, row.rowNumber, JSON.stringify(row), row.normalizedTerm, wordId, isNew ? "IMPORTED" : "EXISTING", now);
    }

    sqlite.prepare(`UPDATE import_batches SET created_words = ?, existing_words = ?, queued_initializations = ?,
      status = 'COMMITTED', completed_at = ? WHERE id = ?`)
      .run(createdWords, existingWords, queuedInitializations, now, batchId);
    return { batchId, createdWords, existingWords, queuedInitializations };
  }).immediate();
}

export class ImportRollbackError extends Error {
  constructor(public readonly code: string, message: string, public readonly details?: unknown) {
    super(message);
    this.name = "ImportRollbackError";
  }
}

function rollbackEligibility(batch: {
  status: string; import_mode: string; reset_learning_progress: number; existing_words: number;
}) {
  if (batch.status === "ROLLED_BACK") return { canRollback: false, reason: "该批次已经撤销。" };
  if (batch.status !== "COMMITTED") return { canRollback: false, reason: "只有已提交的导入批次可以撤销。" };
  if (batch.reset_learning_progress) return { canRollback: false, reason: "该批次重置过学习进度，无法无损恢复。" };
  if (batch.existing_words > 0 && batch.import_mode !== "SKIP_EXISTING") {
    return { canRollback: false, reason: "该批次修改过已有词条内容，无法保证完整回滚。" };
  }
  return { canRollback: true, reason: null };
}

export function listImportBatches(limit = 50) {
  const rows = sqlite.prepare("SELECT * FROM import_batches ORDER BY created_at DESC LIMIT ?").all(limit) as Array<Record<string, unknown>>;
  return rows.map((row) => ({
    id: Number(row.id),
    filename: String(row.filename),
    importMode: String(row.import_mode),
    resetLearningProgress: Boolean(row.reset_learning_progress),
    totalRows: Number(row.total_rows),
    validRows: Number(row.valid_rows),
    invalidRows: Number(row.invalid_rows),
    duplicateRows: Number(row.duplicate_rows),
    createdWords: Number(row.created_words),
    existingWords: Number(row.existing_words),
    queuedInitializations: Number(row.queued_initializations),
    status: String(row.status),
    createdAt: new Date(Number(row.created_at)).toISOString(),
    completedAt: row.completed_at ? new Date(Number(row.completed_at)).toISOString() : null,
    rolledBackAt: row.rolled_back_at ? new Date(Number(row.rolled_back_at)).toISOString() : null,
    rollback: rollbackEligibility({
      status: String(row.status),
      import_mode: String(row.import_mode),
      reset_learning_progress: Number(row.reset_learning_progress),
      existing_words: Number(row.existing_words),
    }),
  }));
}

export function rollbackImportBatch(batchId: number) {
  const batch = sqlite.prepare("SELECT * FROM import_batches WHERE id = ?").get(batchId) as {
    id: number; status: string; import_mode: string; reset_learning_progress: number;
    existing_words: number; created_at: number;
  } | undefined;
  if (!batch) throw new ImportRollbackError("IMPORT_BATCH_NOT_FOUND", "导入批次不存在。");
  const eligibility = rollbackEligibility(batch);
  if (!eligibility.canRollback) throw new ImportRollbackError("IMPORT_BATCH_NOT_ROLLBACKABLE", eligibility.reason ?? "该批次不能撤销。");

  const createdRows = sqlite.prepare(`SELECT ir.word_id, w.term FROM import_rows ir
    JOIN words w ON w.id = ir.word_id
    WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED' AND ir.word_id IS NOT NULL`)
    .all(batchId) as Array<{ word_id: number; term: string }>;
  const createdIds = new Set(createdRows.map((row) => row.word_id));
  if (createdIds.size === 0) {
    const now = Date.now();
    sqlite.prepare("UPDATE import_batches SET status = 'ROLLED_BACK', rolled_back_at = ? WHERE id = ?").run(now, batchId);
    return { batchId, deletedWords: 0, status: "ROLLED_BACK" as const };
  }

  const blockers = new Set<number>();
  const blockerQueries = [
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN review_logs r ON r.word_id = ir.word_id
      WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED'`,
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN review_cards c ON c.word_id = ir.word_id AND c.reps > 0
      WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED'`,
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN study_session_items si ON si.word_id = ir.word_id
      WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED'`,
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN words w ON w.id = ir.word_id
      WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED'
        AND (w.user_note IS NOT NULL OR w.is_suspended = 1)`,
  ];
  for (const query of blockerQueries) {
    for (const row of sqlite.prepare(query).all(batchId) as Array<{ word_id: number }>) blockers.add(row.word_id);
  }
  const laterImports = sqlite.prepare(`SELECT DISTINCT original.word_id
    FROM import_rows original
    JOIN import_rows later ON later.word_id = original.word_id AND later.import_batch_id <> original.import_batch_id
    JOIN import_batches later_batch ON later_batch.id = later.import_batch_id
    WHERE original.import_batch_id = ? AND original.status = 'IMPORTED'
      AND later_batch.status = 'COMMITTED' AND later_batch.created_at > ?`)
    .all(batchId, batch.created_at) as Array<{ word_id: number }>;
  for (const row of laterImports) blockers.add(row.word_id);

  if (blockers.size > 0) {
    const blockedWords = createdRows.filter((row) => blockers.has(row.word_id)).slice(0, 30);
    throw new ImportRollbackError(
      "IMPORT_BATCH_HAS_DEPENDENCIES",
      `有 ${blockers.size} 个词条已经产生学习记录、会话或后续导入，不能安全撤销。`,
      { blockedCount: blockers.size, blockedWords },
    );
  }

  const now = Date.now();
  const result = sqlite.transaction(() => {
    const deleted = sqlite.prepare(`DELETE FROM words WHERE id IN (
      SELECT word_id FROM import_rows WHERE import_batch_id = ? AND status = 'IMPORTED' AND word_id IS NOT NULL
    )`).run(batchId);
    sqlite.prepare(`UPDATE import_batches SET status = 'ROLLED_BACK', rolled_back_at = ? WHERE id = ?`)
      .run(now, batchId);
    return deleted.changes;
  }).immediate();
  return { batchId, deletedWords: result, status: "ROLLED_BACK" as const };
}

export async function getImportPreview(token: string) {
  const rows = await db.select().from(importPreviews).where(and(eq(importPreviews.token, token), sql`${importPreviews.expiresAt} > ${new Date()}`)).limit(1);
  return rows[0] ?? null;
}
