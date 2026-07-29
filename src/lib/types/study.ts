import type { DictionaryContent } from "./content";
import type { EntryType, QuestionType } from "./core";

export interface StudyItemView {
  itemId: number; position: number; taskType: "NEW" | "REVIEW" | "WRONG" | "LISTENING" | "SPELLING"; questionType: QuestionType;
  choices?: string[];
  word: { id: number; term: string; sourceLanguage: string; targetLanguage: string; entryType: EntryType; content: DictionaryContent };
}
