import type { QuestionType } from "@/lib/types";

export interface DailySuggestionMetrics {
  reviewCount: number;
  correctCount: number;
  accuracy: number | null;
  againCount: number;
  hardCount: number;
  skippedCount: number;
  sessionCount: number;
  averageDurationMs: number | null;
  studyMinutes: number;
  completionRate: number | null;
  questionAccuracy: Record<string, number | null>;
}

export interface RecommendedStudyItem {
  wordId: number;
  term: string;
  definition: string | null;
  reason: string;
  questionType: QuestionType;
  score: number;
}

export interface DailyAiSuggestion {
  dateKey: string;
  sourceDateKey: string;
  qualityScore: number | null;
  metrics: DailySuggestionMetrics;
  headline: string;
  summary: string;
  strengths: string[];
  risks: string[];
  actions: string[];
  recommendedItems: RecommendedStudyItem[];
  generator: "AI" | "RULE_BASED";
  configured: boolean;
  providerId: string | null;
  model: string | null;
  generationWarning: string | null;
  generatedAt: string;
}

export interface ReviewRow {
  word_id: number;
  reviewed_at: number;
  rating: string;
  question_type: string;
  is_correct: number;
  duration_ms: number | null;
  study_session_id: number | null;
}

export interface CandidateAccumulator {
  wordId: number;
  attempts: number;
  incorrect: number;
  again: number;
  hard: number;
  durationTotal: number;
  durationCount: number;
  questionErrors: Map<string, number>;
  wrongActive: boolean;
  wrongCount: number;
  hardCount: number;
  dueAt: number | null;
  difficulty: number;
  lapses: number;
  fallback: boolean;
}

export interface SuggestionCandidate extends RecommendedStudyItem {
  attempts: number;
  incorrect: number;
  again: number;
  hard: number;
  wrongActive: boolean;
  overdueDays: number;
}

export interface SuggestionContent {
  headline: string;
  summary: string;
  strengths: string[];
  risks: string[];
  actions: string[];
}

export interface AiSuggestionOutput extends SuggestionContent {
  recommended: Array<{ wordId: number; reason: string }>;
}

export interface SuggestionConfiguration {
  configured: boolean;
  providerId: string | null;
  model: string | null;
}

export interface GeneratedAiSuggestion {
  output: AiSuggestionOutput;
  providerId: string;
  model: string;
}
