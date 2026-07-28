import type { QuestionType, ReviewRating } from "@/lib/types";

export interface AnswerInput {
  clientAnswerId: string;
  wordId: number;
  studySessionId?: number;
  studySessionItemId?: number;
  rating: ReviewRating;
  questionType: QuestionType;
  userAnswer?: string;
  durationMs?: number;
}

export interface ExistingReviewLog {
  id: number;
  word_id: number;
  study_session_id: number | null;
  study_session_item_id: number | null;
  rating: ReviewRating;
  is_correct: number;
  expected_answer: string | null;
}

export interface ReviewWordRow {
  id: number;
  term: string;
  normalized_term: string;
  source_language: string;
  target_language: string;
  initialization_status: string;
  is_suspended: number;
  definitions_json: string | null;
}

export interface ReviewCardRow {
  due_at: number;
  stability: number;
  difficulty: number;
  elapsed_days: number;
  scheduled_days: number;
  reps: number;
  lapses: number;
  fsrs_state: number;
  learning_steps: number;
  last_review_at: number | null;
}

export interface ReviewStatistics {
  total: number;
  correct: number;
  recent_again: number;
  avg_duration: number | null;
}

export interface WrongStateResult {
  active: boolean;
  consecutiveCorrect: number;
}
