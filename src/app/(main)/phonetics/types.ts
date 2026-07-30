import type { LeaderboardSummary } from "@/lib/types";
import type { GameAnswerState, GamePhase } from "@/lib/game-types";

export type PhoneticAccent = "US" | "UK";
export type PhoneticChallengeType = "SOUND_TO_PHONETIC" | "PHONETIC_TO_WORD" | "WORD_TO_PHONETIC";
export type PhoneticPhase = GamePhase;

export interface PhoneticGameItem {
  itemId: number;
  wordId: number;
  term: string;
  definition: string;
  phonetic: string;
  phoneticAccent: "US" | "UK";
  challengeType: PhoneticChallengeType;
  choices: string[];
  priority: "WRONG" | "RECENT_MISTAKE" | "DUE" | "NORMAL";
}

export interface PhoneticGameSession {
  sessionId: number;
  accent: PhoneticAccent;
  durationSeconds: number;
  items: PhoneticGameItem[];
}

export interface PhoneticGameResult {
  sessionId: number;
  score: number;
  firstTryCorrect: number;
  recovered: number;
  missed: number;
  total: number;
  accuracy: number;
  mistakeCount: number;
  maxCombo: number;
  elapsedMs: number;
  leaderboard?: LeaderboardSummary;
}

export type PhoneticAnswerState = GameAnswerState;
