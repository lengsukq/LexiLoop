import { ApiError } from "@/lib/api";
import { recordScore } from "@/modules/leaderboard/service";
import { selectPracticeCandidates } from "@/modules/practice/candidates";
import {
  closeOpenPracticeSessions,
  completePracticeSession,
  createPracticeSession,
} from "@/modules/practice/sessions";
import type { PracticeAnswer, PracticeCandidate } from "@/modules/practice/types";

const MINIMUM_PAIR_COUNT = 4;
const MAXIMUM_PAIR_COUNT = 8;
const MINIMUM_DURATION_SECONDS = 30;
const MAXIMUM_DURATION_SECONDS = 180;

export interface MatchingPair {
  itemId: number;
  wordId: number;
  term: string;
  definition: string;
  priority: PracticeCandidate["priority"];
}

export interface MatchingSessionPayload {
  sessionId: number;
  pairCount: number;
  durationSeconds: number;
  pairs: MatchingPair[];
}

export interface MatchingResultInput {
  itemId: number;
  wordId: number;
  matched: boolean;
  hadMistake: boolean;
  durationMs?: number;
}

function boundedInteger(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, Math.round(value)));
}

function toPracticeAnswer(result: MatchingResultInput): PracticeAnswer {
  return {
    itemId: result.itemId,
    wordId: result.wordId,
    solved: result.matched,
    hadMistake: result.hadMistake,
    durationMs: result.durationMs,
  };
}

export async function startMatchingSession(options: {
  pairCount: number;
  durationSeconds: number;
}): Promise<MatchingSessionPayload> {
  const pairCount = boundedInteger(options.pairCount, MINIMUM_PAIR_COUNT, MAXIMUM_PAIR_COUNT);
  const durationSeconds = boundedInteger(
    options.durationSeconds,
    MINIMUM_DURATION_SECONDS,
    MAXIMUM_DURATION_SECONDS,
  );
  const now = Date.now();
  await closeOpenPracticeSessions("MATCH_GAME", now);

  const candidates = await selectPracticeCandidates({
    count: pairCount,
    now,
    excludeWordsInActiveSessions: true,
  });
  if (candidates.length < MINIMUM_PAIR_COUNT) throw new ApiError("NOT_ENOUGH_MATCHING_WORDS");

  const session = await createPracticeSession(candidates, {
    sourceType: "MATCH_GAME",
    sessionType: "WRONG_WORDS",
    questionType: "EN_TO_ZH_CHOICE",
    defaultTaskType: "NEW",
    classifyDueAsReview: true,
  }, now);
  const itemIds = new Map(session.items.map((item) => [item.wordId, item.itemId]));

  return {
    sessionId: session.sessionId,
    pairCount: candidates.length,
    durationSeconds,
    pairs: candidates.map((candidate) => ({
      itemId: itemIds.get(candidate.id)!,
      wordId: candidate.id,
      term: candidate.term,
      definition: candidate.definition,
      priority: candidate.priority,
    })),
  };
}

function calculateMatchingScore(input: {
  firstTryCorrect: number;
  recovered: number;
  maxCombo: number;
  mistakeCount: number;
  durationSeconds: number;
  elapsedMs: number;
}): number {
  const remainingMs = Math.max(0, input.durationSeconds * 1000 - input.elapsedMs);
  return Math.max(0, Math.round(
    input.firstTryCorrect * 120
    + input.recovered * 70
    + Math.min(600, remainingMs / 100)
    + input.maxCombo * 15
    - input.mistakeCount * 25,
  ));
}

export async function completeMatchingSession(input: {
  sessionId: number;
  results: MatchingResultInput[];
  elapsedMs: number;
  durationSeconds: number;
  mistakeCount: number;
  maxCombo: number;
}) {
  try {
    const summary = await completePracticeSession({
      sessionId: input.sessionId,
      sourceType: "MATCH_GAME",
      clientAnswerPrefix: "match",
      answers: input.results.map(toPracticeAnswer),
      elapsedMs: input.elapsedMs,
      mistakeCount: input.mistakeCount,
      maxCombo: input.maxCombo,
      failureAnswer: "__MATCH_MISTAKE__",
    });
    const score = calculateMatchingScore({
      ...summary,
      durationSeconds: input.durationSeconds,
    });
    const leaderboard = await recordScore({
      gameMode: "MATCH",
      score,
      maxCombo: summary.maxCombo,
      accuracy: summary.accuracy,
      elapsedMs: summary.elapsedMs,
    });
    return {
      ...summary,
      score,
      leaderboard,
    };
  } catch (error) {
    if (error instanceof ApiError && error.code === "PRACTICE_SESSION_NOT_FOUND") {
      throw new ApiError("MATCH_SESSION_NOT_FOUND");
    }
    throw error;
  }
}
