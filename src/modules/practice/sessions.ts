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
import { processReviewAnswersInTransaction } from "@/modules/reviews/service";
import { getSettings } from "@/modules/settings/service";
import { boundedActiveDurationMs, closeStudySessionWithActiveDuration } from "@/modules/reviews/duration";
import type { AnswerInput } from "@/modules/reviews/types";
import type { QuestionType } from "@/lib/types";

interface CompletionRow {
  item_id: number;
  word_id: number;
  question_type: QuestionType;
  status: string;
  term: string;
  target_language: string;
  definitions_json: string;
}

export async function closeOpenPracticeSessions(sourceTypePattern: string, now = Date.now()): Promise<void> {
  const sessions = await sqlite.prepare(`SELECT id FROM study_sessions
    WHERE source_type LIKE ? AND completed_at IS NULL`).all(sourceTypePattern) as Array<{ id: number }>;
  if (!sessions.length) return;

  await sqlite.transaction(async () => {
    const skipPendingItems = sqlite.prepare(`UPDATE study_session_items
      SET status = 'SKIPPED', answered_at = ?, skip_reason = 'SESSION_EXPIRED'
      WHERE study_session_id = ? AND status = 'PENDING'`);
    const updateCounts = sqlite.prepare(`UPDATE study_sessions
      SET completed_count = completed_count + ?, skipped_count = skipped_count + ? WHERE id = ?`);

    for (const session of sessions) {
      const skipped = await skipPendingItems.run(now, session.id);
      await updateCounts.run(skipped.changes, skipped.changes, session.id);
      await closeStudySessionWithActiveDuration(session.id, now);
    }
  }).immediate();
}

function taskTypeFor(candidate: PracticeCandidate, config: PracticeSessionConfig, now: number): PracticeTaskType {
  if (candidate.wrong_active) return "WRONG";
  if (config.classifyDueAsReview && candidate.due_at !== null && candidate.due_at <= now) return "REVIEW";
  return config.defaultTaskType;
}

export async function createPracticeSession(
  candidates: readonly PracticeCandidate[],
  config: PracticeSessionConfig,
  now = Date.now(),
): Promise<{ sessionId: number; items: PracticeSessionItemReference[] }> {
  const sessionId = await sqlite.transaction(async () => {
    const session = await sqlite.prepare(`INSERT INTO study_sessions
      (session_type, source_type, started_at, completed_at, planned_count, completed_count,
       correct_count, wrong_count, skipped_count, created_at)
      VALUES (?, ?, ?, NULL, ?, 0, 0, 0, 0, ?)`)
      .run(config.sessionType, config.sourceType, now, candidates.length, now);
    const id = Number(session.lastInsertRowid);
    const insertItem = sqlite.prepare(`INSERT INTO study_session_items
      (study_session_id, position, word_id, task_type, question_type, status, created_at)
      VALUES (?, ?, ?, ?, ?, 'PENDING', ?)`);

    for (const [index, candidate] of candidates.entries()) {
      await insertItem.run(
        id,
        index,
        candidate.id,
        taskTypeFor(candidate, config, now),
        config.questionType,
        now,
      );
    }
    return id;
  }).immediate();

  const items = await sqlite.prepare(`SELECT id, word_id FROM study_session_items
    WHERE study_session_id = ? ORDER BY position ASC`).all(sessionId) as Array<{
      id: number;
      word_id: number;
    }>;

  return {
    sessionId,
    items: items.map((item) => ({ itemId: item.id, wordId: item.word_id })),
  };
}

async function loadCompletionRows(sessionId: number, sourceType: string): Promise<CompletionRow[]> {
  const session = await sqlite.prepare(`SELECT source_type FROM study_sessions WHERE id = ?`).get(sessionId) as {
    source_type: string | null;
  } | undefined;
  if (!session || session.source_type !== sourceType) throw new Error("PRACTICE_SESSION_NOT_FOUND");

  return await sqlite.prepare(`SELECT i.id AS item_id, i.word_id, i.question_type, i.status,
      w.term, w.target_language, c.definitions_json
    FROM study_session_items i
    JOIN words w ON w.id = i.word_id
    JOIN word_contents c ON c.word_id = w.id
    WHERE i.study_session_id = ? ORDER BY i.position ASC`).all(sessionId) as CompletionRow[];
}

function correctAnswer(row: CompletionRow): string {
  if (row.question_type !== "EN_TO_ZH_CHOICE") return row.term;
  return extractPreferredDefinition(row.definitions_json, row.target_language) ?? "";
}

export async function completePracticeSession(
  input: PracticeCompletionInput,
): Promise<PracticeCompletionSummary> {
  const rows = await loadCompletionRows(input.sessionId, input.sourceType);
  const submitted = new Map(input.answers.map((answer) => [`${answer.itemId}:${answer.wordId}`, answer]));
  const averageDuration = boundedActiveDurationMs(input.elapsedMs / Math.max(1, rows.length)) ?? 0;
  let firstTryCorrect = 0;
  let recovered = 0;
  let missed = 0;

  const pendingAnswers: AnswerInput[] = [];
  for (const row of rows) {
    const answer = submitted.get(`${row.item_id}:${row.word_id}`);
    const solved = Boolean(answer?.solved);
    const hadMistake = Boolean(answer?.hadMistake);
    if (solved && !hadMistake) firstTryCorrect += 1;
    else if (solved) recovered += 1;
    else missed += 1;

    if (row.status !== "PENDING") continue;
    pendingAnswers.push({
      clientAnswerId: `${input.clientAnswerPrefix}-${input.sessionId}-${row.item_id}`,
      wordId: row.word_id,
      studySessionId: input.sessionId,
      studySessionItemId: row.item_id,
      rating: solved && !hadMistake ? "GOOD" : "AGAIN",
      questionType: row.question_type,
      userAnswer: solved && !hadMistake ? correctAnswer(row) : input.failureAnswer,
      durationMs: boundedActiveDurationMs(answer?.durationMs ?? averageDuration) ?? 0,
    });
  }

  if (pendingAnswers.length > 0) {
    const settings = await getSettings();
    await processReviewAnswersInTransaction(pendingAnswers, settings);
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
