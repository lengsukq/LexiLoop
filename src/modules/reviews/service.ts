import { sqlite } from "@/db/client";
import type { AppSettings } from "@/lib/types";
import { getSettings } from "@/modules/settings/service";
import { evaluateReviewAnswer } from "./answer-evaluation";
import { cardFromRow, emptyCard, previewCard, scheduleCard } from "./fsrs";
import { calculateMasteryScore, determineMasteryLevel } from "./mastery";
import {
  assertIdempotencyContext,
  assertReviewableWord,
  buildIdempotentResult,
  claimStudyItem,
  finalizeStudySession,
  findExistingReview,
  findReviewCard,
  findReviewWord,
  insertReviewLog,
  loadReviewStatistics,
  saveReviewCard,
  updateWordMastery,
  upsertWordReviewStats,
} from "./repository";
import type { AnswerInput } from "./types";
import { updateWrongWordState } from "./wrong-state";
import { scheduleAdaptiveFollowUp } from "@/modules/study/adaptive";
import type { ReviewRating } from "@/lib/types";

export interface ReviewAnswerResult {
  idempotent: boolean;
  reviewLogId: number;
  isCorrect: boolean;
  rating: ReviewRating;
  expectedAnswer: string;
  nextDueAt: string | null;
  scheduledDays: number;
  masteryScore: number;
  masteryLevel: string;
  wrongWordActive: boolean;
  adaptiveFollowUp: { questionType: string; position: number; repetition: number } | null;
}

/**
 * Shared answer-processing pipeline. Must run inside a transaction so the whole
 * review, stats update, mastery and session bookkeeping stay atomic.
 */
function processReviewAnswerCore(input: AnswerInput, settings: AppSettings): ReviewAnswerResult {
  const existing = findExistingReview(input.clientAnswerId);
  if (existing) {
    assertIdempotencyContext(existing, input);
    return buildIdempotentResult(existing);
  }

  const reviewedAt = new Date();
  const now = reviewedAt.getTime();
  claimStudyItem(input, now);

  const word = findReviewWord(input.wordId);
  assertReviewableWord(word);
  const evaluation = evaluateReviewAnswer(input, word);
  const previousCard = findReviewCard(word.id);
  const before = previousCard ? cardFromRow(previousCard) : emptyCard(reviewedAt);
  const after = scheduleCard(before, reviewedAt, evaluation.effectiveRating, settings.targetRetentionRate).card;

  saveReviewCard(word.id, after, now);
  const reviewLogId = insertReviewLog({
    answer: input,
    reviewedAt: now,
    rating: evaluation.effectiveRating,
    presentedPrompt: evaluation.presentedPrompt,
    expectedAnswer: evaluation.expectedAnswer,
    isCorrect: evaluation.isCorrect,
    before,
    after,
  });
  upsertWordReviewStats({
    wordId: word.id,
    reviewedAt: now,
    rating: evaluation.effectiveRating,
    isCorrect: evaluation.isCorrect,
    durationMs: input.durationMs ?? null,
  });

  const wrongState = updateWrongWordState(word.id, evaluation.effectiveRating, evaluation.isCorrect, now);
  const statistics = loadReviewStatistics(word.id, now);
  const masteryInput = {
    stability: after.stability,
    scheduledDays: after.scheduled_days,
    reps: after.reps,
    lapses: after.lapses,
    accuracy: statistics.total ? statistics.correct / statistics.total : 0,
    consecutiveCorrect: wrongState.consecutiveCorrect,
    activeWrongWord: wrongState.active,
    recentAgain: statistics.recent_again ?? 0,
    avgDurationMs: statistics.avg_duration ?? undefined,
  };
  const masteryScore = calculateMasteryScore(masteryInput);
  const masteryLevel = determineMasteryLevel(masteryInput, masteryScore);
  updateWordMastery(word.id, masteryScore, masteryLevel, now);
  const adaptiveFollowUp = scheduleAdaptiveFollowUp({
    sessionId: input.studySessionId!,
    itemId: input.studySessionItemId!,
    wordId: word.id,
    currentQuestionType: input.questionType,
    entryType: word.content_type as "WORD" | "PHRASE" | "SENTENCE",
    isCorrect: evaluation.isCorrect || evaluation.effectiveRating === "EASY",
    rating: evaluation.effectiveRating,
    now,
  });
  finalizeStudySession(input.studySessionId!, evaluation.isCorrect, now);

  return {
    idempotent: false,
    reviewLogId,
    isCorrect: evaluation.isCorrect,
    rating: evaluation.effectiveRating,
    expectedAnswer: evaluation.expectedAnswer,
    nextDueAt: after.due.toISOString(),
    scheduledDays: after.scheduled_days,
    masteryScore,
    masteryLevel,
    wrongWordActive: wrongState.active,
    adaptiveFollowUp,
  };
}

export async function processReviewAnswer(input: AnswerInput): Promise<ReviewAnswerResult> {
  const settings = await getSettings();
  return sqlite.transaction(() => processReviewAnswerCore(input, settings)).immediate();
}

/** Processes a batch of answers inside a single transaction (practice/game completion). */
export function processReviewAnswersInTransaction(
  inputs: readonly AnswerInput[],
  settings: AppSettings,
): ReviewAnswerResult[] {
  return sqlite.transaction(() => inputs.map((input) => processReviewAnswerCore(input, settings))).immediate();
}

export async function getReviewPreview(wordId: number) {
  const settings = await getSettings();
  const row = findReviewCard(wordId);
  const card = row ? cardFromRow(row) : emptyCard(new Date());
  return previewCard(card, new Date(), settings.targetRetentionRate).map((item) => ({
    ...item,
    nextDueAt: item.nextDueAt.toISOString(),
  }));
}
