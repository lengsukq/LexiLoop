import type { PhoneticGameItem } from "./types";

/** 该题目的正确选项：音节题选词，其余题型选音标。 */
export function correctChoice(item: PhoneticGameItem): string {
  return item.challengeType === "PHONETIC_TO_WORD" ? item.term : item.phonetic;
}
