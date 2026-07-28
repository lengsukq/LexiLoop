import { recordScore } from "@/modules/leaderboard/service";
import { createPhoneticItems, selectPhoneticCandidates } from "@/modules/phonetics/selection";
import type {
  PhoneticAccent,
  PhoneticGameAnswer,
  PhoneticGameSession,
} from "@/modules/phonetics/types";
import {
  closeOpenPracticeSessions,
  completePracticeSession,
  createPracticeSession,
} from "@/modules/practice/sessions";

export { PHONETIC_ACCENTS } from "@/modules/phonetics/types";
export type { PhoneticAccent, PhoneticGameItem, PhoneticGameSession } from "@/modules/phonetics/types";

const SESSION_SOURCE = "GAME_PHONETICS";
const GAME_ITEM_COUNT = 10;
const GAME_DURATION_SECONDS = 75;
const MINIMUM_ITEMS = 4;

export function startPhoneticGame(accent: PhoneticAccent): PhoneticGameSession {
  const now = Date.now();
  closeOpenPracticeSessions(SESSION_SOURCE, now);
  const candidates = selectPhoneticCandidates({ count: GAME_ITEM_COUNT, accent, now });
  if (candidates.length < MINIMUM_ITEMS) throw new Error("NOT_ENOUGH_PHONETIC_WORDS");

  const session = createPracticeSession(candidates, {
    sourceType: SESSION_SOURCE,
    sessionType: "LISTENING",
    questionType: "LISTENING_SPELLING",
    defaultTaskType: "LISTENING",
  }, now);
  const itemIds = new Map(session.items.map((item) => [item.wordId, item.itemId]));

  return {
    sessionId: session.sessionId,
    accent,
    durationSeconds: GAME_DURATION_SECONDS,
    items: createPhoneticItems(candidates, itemIds),
  };
}

function calculateScore(summary: {
  firstTryCorrect: number;
  recovered: number;
  maxCombo: number;
  mistakeCount: number;
}): number {
  return Math.max(0, Math.round(
    summary.firstTryCorrect * 120
    + summary.recovered * 60
    + summary.maxCombo * 15
    - summary.mistakeCount * 20,
  ));
}

export async function completePhoneticGame(input: {
  sessionId: number;
  answers: PhoneticGameAnswer[];
  elapsedMs: number;
  mistakeCount: number;
  maxCombo: number;
}) {
  try {
    const summary = await completePracticeSession({
      sessionId: input.sessionId,
      sourceType: SESSION_SOURCE,
      clientAnswerPrefix: "phonetics",
      answers: input.answers,
      elapsedMs: input.elapsedMs,
      mistakeCount: input.mistakeCount,
      maxCombo: input.maxCombo,
      failureAnswer: "__PHONETIC_MISTAKE__",
    });
    const score = calculateScore(summary);
    const leaderboard = recordScore({
      gameMode: "PHONETICS",
      score,
      maxCombo: summary.maxCombo,
      accuracy: summary.accuracy,
      elapsedMs: summary.elapsedMs,
    });
    return { ...summary, score, leaderboard };
  } catch (error) {
    if (error instanceof Error && error.message === "PRACTICE_SESSION_NOT_FOUND") {
      throw new Error("PHONETIC_SESSION_NOT_FOUND");
    }
    throw error;
  }
}
