import { recordScore } from "@/modules/leaderboard/service";
import { completePracticeSession } from "@/modules/practice/sessions";
import type { PracticeAnswer } from "@/modules/practice/types";
import type { GameMode } from "./service";

function calculateGameScore(summary: { firstTryCorrect: number; recovered: number; maxCombo: number; mistakeCount: number }): number {
  return Math.max(0, Math.round(summary.firstTryCorrect * 100 + summary.recovered * 55 + summary.maxCombo * 12 - summary.mistakeCount * 20));
}

export async function completeGameSession(input: {
  sessionId: number; mode: GameMode; answers: PracticeAnswer[]; elapsedMs: number; mistakeCount: number; maxCombo: number;
}) {
  try {
    const summary = await completePracticeSession({
      sessionId: input.sessionId, sourceType: `GAME_${input.mode}`, clientAnswerPrefix: `game-${input.mode}`,
      answers: input.answers, elapsedMs: input.elapsedMs, mistakeCount: input.mistakeCount, maxCombo: input.maxCombo,
      failureAnswer: "__GAME_MISTAKE__",
    });
    const score = calculateGameScore(summary);
    const leaderboard = await recordScore({ gameMode: input.mode, score, maxCombo: summary.maxCombo, accuracy: summary.accuracy, elapsedMs: summary.elapsedMs });
    return { ...summary, mode: input.mode, score, leaderboard };
  } catch (error) {
    if (error instanceof Error && error.message === "PRACTICE_SESSION_NOT_FOUND") throw new Error("GAME_SESSION_NOT_FOUND");
    throw error;
  }
}
