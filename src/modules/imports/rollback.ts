import { sqlite } from "@/db/client";

export class ImportRollbackError extends Error {
  constructor(public readonly code: string, message: string, public readonly details?: unknown) {
    super(message);
    this.name = "ImportRollbackError";
  }
}

type BatchState = { status: string; import_mode: string; reset_learning_progress: number; existing_words: number };

function rollbackEligibility(batch: BatchState) {
  if (batch.status === "ROLLED_BACK") return { canRollback: false, reason: "该批次已经撤销。" };
  if (batch.status !== "COMMITTED") return { canRollback: false, reason: "只有已提交的导入批次可以撤销。" };
  if (batch.reset_learning_progress) return { canRollback: false, reason: "该批次重置过学习进度，无法无损恢复。" };
  if (batch.existing_words > 0 && batch.import_mode !== "SKIP_EXISTING") return { canRollback: false, reason: "该批次修改过已有词条内容，无法保证完整回滚。" };
  return { canRollback: true, reason: null };
}

function mapBatch(row: Record<string, unknown>) {
  return {
    id: Number(row.id), filename: String(row.filename), importMode: String(row.import_mode),
    resetLearningProgress: Boolean(row.reset_learning_progress), totalRows: Number(row.total_rows),
    validRows: Number(row.valid_rows), invalidRows: Number(row.invalid_rows), duplicateRows: Number(row.duplicate_rows),
    createdWords: Number(row.created_words), existingWords: Number(row.existing_words),
    queuedInitializations: Number(row.queued_initializations), status: String(row.status),
    createdAt: new Date(Number(row.created_at)).toISOString(),
    completedAt: row.completed_at ? new Date(Number(row.completed_at)).toISOString() : null,
    rolledBackAt: row.rolled_back_at ? new Date(Number(row.rolled_back_at)).toISOString() : null,
    rollback: rollbackEligibility({ status: String(row.status), import_mode: String(row.import_mode), reset_learning_progress: Number(row.reset_learning_progress), existing_words: Number(row.existing_words) }),
  };
}

export function listImportBatches(limit = 50) {
  return (sqlite.prepare("SELECT * FROM import_batches ORDER BY created_at DESC LIMIT ?").all(limit) as Array<Record<string, unknown>>).map(mapBatch);
}

export function rollbackImportBatch(batchId: number) {
  const batch = sqlite.prepare("SELECT * FROM import_batches WHERE id = ?").get(batchId) as (BatchState & { id: number; created_at: number }) | undefined;
  if (!batch) throw new ImportRollbackError("IMPORT_BATCH_NOT_FOUND", "导入批次不存在。");
  const eligibility = rollbackEligibility(batch);
  if (!eligibility.canRollback) throw new ImportRollbackError("IMPORT_BATCH_NOT_ROLLBACKABLE", eligibility.reason ?? "该批次不能撤销。");
  const createdRows = sqlite.prepare(`SELECT ir.word_id, w.term FROM import_rows ir JOIN words w ON w.id = ir.word_id
    WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED' AND ir.word_id IS NOT NULL`).all(batchId) as Array<{ word_id: number; term: string }>;
  const createdIds = new Set(createdRows.map((row) => row.word_id));
  if (!createdIds.size) {
    const now = Date.now();
    sqlite.prepare("UPDATE import_batches SET status = 'ROLLED_BACK', rolled_back_at = ? WHERE id = ?").run(now, batchId);
    return { batchId, deletedWords: 0, status: "ROLLED_BACK" as const };
  }
  const blockers = new Set<number>();
  const blockerQueries = [
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN review_logs r ON r.word_id = ir.word_id WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED'`,
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN review_cards c ON c.word_id = ir.word_id AND c.reps > 0 WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED'`,
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN study_session_items si ON si.word_id = ir.word_id WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED'`,
    `SELECT DISTINCT ir.word_id FROM import_rows ir JOIN words w ON w.id = ir.word_id WHERE ir.import_batch_id = ? AND ir.status = 'IMPORTED' AND (w.user_note IS NOT NULL OR w.is_suspended = 1)`,
  ];
  for (const query of blockerQueries) for (const row of sqlite.prepare(query).all(batchId) as Array<{ word_id: number }>) blockers.add(row.word_id);
  const laterImports = sqlite.prepare(`SELECT DISTINCT original.word_id FROM import_rows original
    JOIN import_rows later ON later.word_id = original.word_id AND later.import_batch_id <> original.import_batch_id
    JOIN import_batches later_batch ON later_batch.id = later.import_batch_id
    WHERE original.import_batch_id = ? AND original.status = 'IMPORTED' AND later_batch.status = 'COMMITTED' AND later_batch.created_at > ?`)
    .all(batchId, batch.created_at) as Array<{ word_id: number }>;
  for (const row of laterImports) blockers.add(row.word_id);
  if (blockers.size) {
    throw new ImportRollbackError("IMPORT_BATCH_HAS_DEPENDENCIES", `有 ${blockers.size} 个词条已经产生学习记录、会话或后续导入，不能安全撤销。`, {
      blockedCount: blockers.size, blockedWords: createdRows.filter((row) => blockers.has(row.word_id)).slice(0, 30),
    });
  }
  const now = Date.now();
  const deleted = sqlite.transaction(() => {
    const result = sqlite.prepare(`DELETE FROM words WHERE id IN (SELECT word_id FROM import_rows WHERE import_batch_id = ? AND status = 'IMPORTED' AND word_id IS NOT NULL)`).run(batchId);
    sqlite.prepare("UPDATE import_batches SET status = 'ROLLED_BACK', rolled_back_at = ? WHERE id = ?").run(now, batchId);
    return result.changes;
  }).immediate();
  return { batchId, deletedWords: deleted, status: "ROLLED_BACK" as const };
}
