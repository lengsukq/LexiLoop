/** Lifecycle phases shared by all practice games (games / match / phonetics). */
export type GamePhase = "setup" | "loading" | "playing" | "saving" | "save-error" | "result";

/** Per-item answer record submitted when a game session completes. */
export interface GameAnswerState {
  itemId: number;
  wordId: number;
  solved: boolean;
  hadMistake: boolean;
  durationMs: number;
}
