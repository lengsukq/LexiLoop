import { sqlite } from "@/db/client";
import { extractPreferredDefinition } from "@/modules/practice/candidates";
import type {
  PracticeCandidate,
  PracticeCompletionInput,
  PracticeCompletionSummary,
  PracticeSessionConfig,
  PracticeSessionItemReference,
  PracticeTaskType,
} from "@/modules/practice/types";
import { processReviewAnswer } from "@/modules/reviews/service";
import type { QuestionType } from "@/lib/types";

const MAX_REVIEW_DURATION_MS = 60 * 60 * 1000;

interface CompletionRow {
  item_id: number;
  word_id: number;
  question_type: QuestionType;
  status: string;
  term: string;
  target_language: string;
  definitions_json: string;
}

export function closeOpenPracticeSessions(sourceTypePattern: string, now = Date.now()): void {
  const sessions = sqlite.prepare(`SELECT id, started_at FROM study_sessions
    WHERE source_type LIKE ? AND completed_at IS NULL`).all(sourceTypePattern) as Array<{
      id: number;
      started_at: number;
    }>;
  if (!sessions.length) return;

  sqlite.transaction(() => {
    const skipPendingItems = sqlite.prepare(`UPDATE study_session_items
      SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED'
      WHERE study_session_id = ? AND status = 'PENDING'`);
    const closeSession = sqlite.prepare(`UPDATE study_sessions
      SET completed_at = ?, duration_ms = ?, completed_count = completed_count + ?,
        skipped_count = skipped_count + ? WHERE id = ?`);

    for (const session of sessions) {
      const skipped = skipPendingItems.run(now, session.id);
      closeSession.run(
        now,
        Math.max(0, now - session.started_at),
        skipped.changes,
        skipped.changes,
        session.id,
      );
    }
  }).immediate();
}

function taskTypeFor(candidate: PracticeCandidate, config: PracticeSessionConfig, now: number): PracticeTaskType {
  if (candidate.wrong_active) return "WRONG";
  if (config.classifyDueAsReview && candidate.due_at !== null && candidate.due_at <= now) return "REVIEW";
  return config.defaultTaskType;
}

export function createPracticeSession(
  candidates: readonly PracticeCandidate[],
  config: PracticeSessionConfig,
  now = Date.now(),
): { sessionId: number; items: PracticeSessionItemReference[] } {
  const sessionId = sqlite.transaction(() => {
    const session = sqlite.prepare(`INSERT INTO study_sessions
      (session_type, source_type, started_at, completed_at, planned_count, completed_count,
       correct_count, wrong_count, skipped_count, created_at)
      VALUES (?, ?, ?, NULL, ?, 0, 0, 0, 0, ?)`)
      .run(config.sessionType, config.sourceType, now, candidates.length, now);
    const id = Number(session.lastInsertRowid);
    const insertItem = sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, created_at)
      VALUES (?, ?, ?, ?, ?, 'PENDING', ?)`);

    candidates.forEach((candidate, index) => {
      insertItem.run(
        id,
        index,
        candidate.id,
        taskTypeFor(candidate, config, now),
        config.questionType,
        now,
      );
    });
    return id;
  }).immediate();

  const items = sqlite.prepare(`SELECT id, word_id FROM study_session_items
    WHERE study_session_id = ? ORDER BY position ASC`).all(sessionId) as Array<{
      id: number;
      word_id: number;
    }>;

  return {
    sessionId,
    items: items.map((item) => ({ itemId: item.id, wordId: item.word_id })),
  };
}

function loadCompletionRows(sessionId: number, sourceType: string): CompletionRow[] {
  const session = sqlite.prepare(`SELECT source_type FROM study_sessions WHERE id = ?`).get(sessionId) as {
    source_type: string | null;
  } | undefined;
  if (!session || session.source_type !== sourceType) throw new Error("PRACTICE_SESSION_NOT_FOUND");

  return sqlite.prepare(`SELECT i.id AS item_id, i.word_id, i.question_type, i.status,
      w.term, w.target_language, c.definitions_json
    FROM study_session_items i
    JOIN words w ON w.id = i.word_id
    JOIN word_contents c ON c.word_id = w.id
    WHERE i.study_session_id = ? ORDER BY i.position ASC`).all(sessionId) as CompletionRow[];
}

function boundedDuration(durationMs: number): number {
  return Math.max(0, Math.min(MAX_REVIEW_DURATION_MS, Math.round(durationMs)));
}

function correctAnswer(row: CompletionRow): string {
  if (row.question_type !== "EN_TO_ZH_CHOICE") return row.term;
  return extractPreferredDefinition(row.definitions_json, row.target_language) ?? "";
}

export async function completePracticeSession(
  input: PracticeCompletionInput,
): Promise<PracticeCompletionSummary> {
  const rows = loadCompletionRows(input.sessionId, input.sourceType);
  const submitted = new Map(input.answers.map((answer) => [`${answer.itemId}:${answer.wordId}`, answer]));
  const averageDuration = boundedDuration(input.elapsedMs / Math.max(1, rows.length));
  let firstTryCorrect = 0;
  let recovered = 0;
  let missed = 0;

  for (const row of rows) {
    const answer = submitted.get(`${row.item_id}:${row.word_id}`);
    const solved = Boolean(answer?.solved);
    const hadMistake = Boolean(answer?.hadMistake);
    if (solved && !hadMistake) firstTryCorrect += 1;
    else if (solved) recovered += 1;
    else missed += 1;

    if (row.status !== "PENDING") continue;
    await processReviewAnswer({
      clientAnswerId: `${input.clientAnswerPrefix}-${input.sessionId}-${row.item_id}`,
      wordId: row.word_id,
      studySessionId: input.sessionId,
      studySessionItemId: row.item_id,
      rating: solved && !hadMistake ? "GOOD" : "AGAIN",
      questionType: row.question_type,
      userAnswer: solved && !hadMistake ? correctAnswer(row) : input.failureAnswer,
      durationMs: boundedDuration(answer?.durationMs ?? averageDuration),
    });
  }

  return {
    sessionId: input.sessionId,
    firstTryCorrect,
    recovered,
    missed,
    total: rows.length,
    accuracy: rows.length ? Math.round(firstTryCorrect / rows.length * 100) : 0,
    mistakeCount: Math.max(0, input.mistakeCount),
    maxCombo: Math.max(0, input.maxCombo),
    elapsedMs: Math.max(0, input.elapsedMs),
  };
}
