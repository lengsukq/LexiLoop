import type { DictionaryContent } from "./content";
import type { EntryType, QuestionType } from "./core";

export interface ClozeExtra {
  sentence: string;
  translation: string | null;
  blankedSentence: string;
}
export interface StudyItemView {
  itemId: number; position: number; taskType: "NEW" | "REVIEW" | "WRONG" | "LISTENING" | "SPELLING"; questionType: QuestionType;
  choices?: string[];
  choiceDefinitions?: Record<string, string>;
  cloze?: ClozeExtra | null;
  letters?: Array<{ id: string; value: string }>;
  word: { id: number; term: string; sourceLanguage: string; targetLanguage: string; entryType: EntryType; content: DictionaryContent };
}
