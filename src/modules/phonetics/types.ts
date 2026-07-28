import type { PracticeAnswer, PracticePriority } from "@/modules/practice/types";

export const PHONETIC_ACCENTS = ["US", "UK"] as const;
export type PhoneticAccent = (typeof PHONETIC_ACCENTS)[number];

export const PHONETIC_CHALLENGE_TYPES = [
  "SOUND_TO_PHONETIC",
  "PHONETIC_TO_WORD",
  "WORD_TO_PHONETIC",
] as const;
export type PhoneticChallengeType = (typeof PHONETIC_CHALLENGE_TYPES)[number];

export interface PhoneticGameItem {
  itemId: number;
  wordId: number;
  term: string;
  definition: string;
  phonetic: string;
  phoneticAccent: "US" | "UK" | "GENERAL";
  challengeType: PhoneticChallengeType;
  choices: string[];
  priority: PracticePriority;
}

export interface PhoneticGameSession {
  sessionId: number;
  accent: PhoneticAccent;
  durationSeconds: number;
  items: PhoneticGameItem[];
}

export type PhoneticGameAnswer = PracticeAnswer;
