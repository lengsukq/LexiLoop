export interface GameItem {
  itemId: number;
  wordId: number;
  term: string;
  definition: string;
  choices: string[];
  choiceDefinitions: Record<string, string>;
  letters: Array<{ id: string; value: string }>;
  priority: "WRONG" | "RECENT_MISTAKE" | "DUE" | "NORMAL";
}
