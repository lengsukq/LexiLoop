import type { QuestionType, StudyItemView } from "@/lib/types";

export type PracticePriority = "WRONG" | "RECENT_MISTAKE" | "DUE" | "NORMAL";
export type PracticeTaskType = StudyItemView["taskType"];
export type PersistedStudyMode = "DAILY" | "NEW_WORDS" | "DUE_REVIEW" | "WRONG_WORDS" | "LISTENING" | "SPELLING";

export interface PracticeCandidateRow {
  id: number;
  term: string;
  normalized_term: string;
  source_language: string;
  target_language: string;
  content_type: string;
  definitions_json: string;
  pronunciations_json: string;
  wrong_active: number;
  wrong_count: number;
  hard_count: number;
  due_at: number | null;
  mastery_score: number;
  recent_again: number;
  recent_hard: number;
}

export interface PracticeCandidate extends PracticeCandidateRow {
  definition: string;
  priority: PracticePriority;
}

export interface PracticeSelectionOptions {
  count: number;
  now: number;
  candidateFilter?: (candidate: PracticeCandidateRow) => boolean;
  excludeWordsInActiveSessions?: boolean;
}

export interface PracticeSessionConfig {
  sourceType: string;
  sessionType: PersistedStudyMode;
  questionType: QuestionType;
  defaultTaskType: PracticeTaskType;
  classifyDueAsReview?: boolean;
}

export interface PracticeSessionItemReference {
  itemId: number;
  wordId: number;
}

export interface PracticeAnswer {
  itemId: number;
  wordId: number;
  solved: boolean;
  hadMistake: boolean;
  durationMs?: number;
}

export interface PracticeCompletionInput {
  sessionId: number;
  sourceType: string;
  clientAnswerPrefix: string;
  answers: PracticeAnswer[];
  elapsedMs: number;
  mistakeCount: number;
  maxCombo: number;
  failureAnswer: string;
}

export interface PracticeCompletionSummary {
  sessionId: number;
  firstTryCorrect: number;
  recovered: number;
  missed: number;
  total: number;
  accuracy: number;
  mistakeCount: number;
  maxCombo: number;
  elapsedMs: number;
}
