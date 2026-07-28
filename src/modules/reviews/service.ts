import { sqlite } from "@/db/client";
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
} from "./repository";
import type { AnswerInput } from "./types";
import { updateWrongWordState } from "./wrong-state";

export async function processReviewAnswer(input: AnswerInput) {
  const settings = await getSettings();
  const transaction = sqlite.transaction(() => {
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
    };
  });
  return transaction.immediate();
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
