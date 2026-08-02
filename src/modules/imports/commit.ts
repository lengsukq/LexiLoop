import { sqlite } from "@/db/client";
import type { ImportMode, ImportPreviewRow, InitializationMode } from "@/lib/types";
import { closeStudySessionWithActiveDuration } from "@/modules/reviews/duration";
import { legacyEntryType } from "./normalizer";

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

async function cancelPendingStudyItemsForWord(wordId: number, now: number): Promise<void> {
  const sessions = await sqlite.prepare(`SELECT study_session_id AS session_id, count(*) AS count
    FROM study_session_items WHERE word_id = ? AND status = 'PENDING' GROUP BY study_session_id`).all(wordId) as Array<{ session_id: number; count: number }>;
  await sqlite.prepare(`UPDATE study_session_items SET status = 'SKIPPED', answered_at = ?, skip_reason = 'PROGRESS_RESET'
    WHERE word_id = ? AND status = 'PENDING'`).run(now, wordId);
  for (const session of sessions) {
    await sqlite.prepare("UPDATE study_sessions SET completed_count = completed_count + ? WHERE id = ?").run(session.count, session.session_id);
    const pending = await sqlite.prepare("SELECT count(*) AS count FROM study_session_items WHERE study_session_id = ? AND status = 'PENDING'").get(session.session_id) as { count: number };
    if (pending.count === 0) closeStudySessionWithActiveDuration(session.session_id, now);
  }
}

async function markWordInitializationQueued(wordId: number, now: number): Promise<void> {
  const content = await sqlite.prepare("SELECT definitions_json FROM word_contents WHERE word_id = ?").get(wordId) as { definitions_json: string } | undefined;
  let hasDefinition = false;
  try { hasDefinition = content ? (JSON.parse(content.definitions_json) as unknown[]).length > 0 : false; } catch { hasDefinition = false; }
  if (!hasDefinition) await sqlite.prepare("UPDATE words SET initialization_status = 'QUEUED', updated_at = ? WHERE id = ?").run(now, wordId);
}

async function enqueueJob(wordId: number, mode: InitializationMode, priority: number, now: number): Promise<boolean> {
  const active = await sqlite.prepare("SELECT id, mode, priority FROM initialization_jobs WHERE word_id = ? AND status IN ('QUEUED','RUNNING') LIMIT 1")
    .get(wordId) as { id: number; mode: string; priority: number } | undefined;
  if (active) {
    await sqlite.prepare(`UPDATE initialization_jobs SET mode = ?, priority = ?, available_at = ?, updated_at = ? WHERE id = ?`)
      .run(strongerMode(active.mode, mode), Math.max(active.priority, priority), now, now, active.id);
    return false;
  }
  await sqlite.prepare(`INSERT INTO initialization_jobs
    (word_id, mode, status, priority, attempt_count, max_attempts, available_at, created_at, updated_at)
    VALUES (?, ?, 'QUEUED', ?, 0, 5, ?, ?, ?)`).run(wordId, mode, priority, now, now, now);
  return true;
}

export async function commitImport(previewToken: string, mode: ImportMode, resetLearningProgress: boolean) {
  const now = Date.now();
  return await sqlite.transaction(async () => {
    const preview = await sqlite.prepare("SELECT * FROM import_previews WHERE token = ?").get(previewToken) as {
      filename: string; file_hash: string; rows_json: string; expires_at: number;
    } | undefined;
    if (!preview || preview.expires_at < now) throw new Error("IMPORT_PREVIEW_EXPIRED");
    if ((await sqlite.prepare("DELETE FROM import_previews WHERE token = ?").run(previewToken)).changes !== 1) throw new Error("IMPORT_PREVIEW_EXPIRED");
    const rows = JSON.parse(preview.rows_json) as ImportPreviewRow[];
    const batch = await sqlite.prepare(`INSERT INTO import_batches
      (filename, file_hash, import_mode, reset_learning_progress, total_rows, valid_rows, invalid_rows, duplicate_rows, status, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?)`).run(
        preview.filename, preview.file_hash, mode, resetLearningProgress ? 1 : 0, rows.length,
        rows.filter((row) => row.status === "NEW" || row.status === "EXISTING").length,
        rows.filter((row) => row.status === "INVALID").length, rows.filter((row) => row.status === "DUPLICATE").length, now);
    const batchId = Number(batch.lastInsertRowid);
    let createdWords = 0;
    let existingWords = 0;
    let queuedInitializations = 0;
    for (const row of rows) {
      if (row.status === "INVALID" || row.status === "DUPLICATE") {
        await sqlite.prepare(`INSERT INTO import_rows
          (import_batch_id, row_number, raw_json, normalized_term, status, error_code, error_message, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).run(batchId, row.rowNumber, JSON.stringify(row), row.normalizedTerm || null, row.status, row.status, row.errors.join("；"), now);
        continue;
      }
      const existing = await sqlite.prepare("SELECT id FROM words WHERE normalized_term = ? AND source_language = ? AND target_language = ? LIMIT 1")
        .get(row.normalizedTerm, row.sourceLanguage, row.targetLanguage) as { id: number } | undefined;
      let wordId: number;
      let isNew = false;
      if (existing) { wordId = existing.id; existingWords += 1; }
      else {
        const inserted = await sqlite.prepare(`INSERT INTO words
          (term, normalized_term, source_language, target_language, source_language_name, target_language_name,
           entry_type, content_type, source_created_at, initialization_status, mastery_level, mastery_score, is_suspended, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', 'NEW', 0, 0, ?, ?)`).run(
            row.term, row.normalizedTerm, row.sourceLanguage, row.targetLanguage, row.sourceLanguageName, row.targetLanguageName,
            legacyEntryType(row.entryType), row.entryType, row.sourceCreatedAt ? new Date(row.sourceCreatedAt).getTime() : null, now, now);
        wordId = Number(inserted.lastInsertRowid); createdWords += 1; isNew = true;
      }
      if (resetLearningProgress && !isNew) {
        cancelPendingStudyItemsForWord(wordId, now);
        for (const table of ["review_logs", "review_cards", "wrong_word_states"]) await sqlite.prepare(`DELETE FROM ${table} WHERE word_id = ?`).run(wordId);
        await sqlite.prepare("UPDATE words SET mastery_level = 'NEW', mastery_score = 0, updated_at = ? WHERE id = ?").run(now, wordId);
      }
      const queueMode = queueModeForImport(mode, isNew);
      if (queueMode) {
        if (await enqueueJob(wordId, queueMode, isNew ? 10 : mode === "FORCE_DICTIONARY_REFRESH" ? 60 : 30, now)) queuedInitializations += 1;
        await markWordInitializationQueued(wordId, now);
      }
      await sqlite.prepare(`INSERT INTO import_rows
        (import_batch_id, row_number, raw_json, normalized_term, word_id, status, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)`).run(batchId, row.rowNumber, JSON.stringify(row), row.normalizedTerm, wordId, isNew ? "IMPORTED" : "EXISTING", now);
    }
    await sqlite.prepare(`UPDATE import_batches SET created_words = ?, existing_words = ?, queued_initializations = ?, status = 'COMMITTED', completed_at = ? WHERE id = ?`)
      .run(createdWords, existingWords, queuedInitializations, now, batchId);
    return { batchId, createdWords, existingWords, queuedInitializations };
  }).immediate();
}
