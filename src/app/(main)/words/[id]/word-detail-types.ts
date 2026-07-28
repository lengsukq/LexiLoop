import type { DictionaryContent, RelatedWordItem } from "@/lib/types";

export type RelationType = "SYNONYM" | "ANTONYM" | "WORD_FAMILY" | "CONFUSED_WITH";

export interface WordDetail {
  id: number;
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  sourceLanguageName: string | null;
  targetLanguageName: string | null;
  entryType: string;
  initializationStatus: string;
  contentSource: string;
  masteryLevel: string;
  masteryScore: number;
  isSuspended: boolean;
  userNote: string | null;
  sourceCreatedAt: string | null;
  createdAt: string;
  updatedAt: string;
  content: DictionaryContent;
  reviewCard: null | {
    dueAt: string;
    stability: number;
    difficulty: number;
    elapsedDays: number;
    scheduledDays: number;
    reps: number;
    lapses: number;
    state: number;
    lastReviewAt: string | null;
  };
  wrongWordState: null | {
    active: boolean;
    wrongCount: number;
    hardCount: number;
    consecutiveCorrect: number;
    lastWrongAt: string | null;
    lastCorrectAt: string | null;
    resolvedAt: string | null;
  };
  recentReviews: Array<{
    id: number;
    reviewedAt: string;
    rating: string;
    questionType: string;
    isCorrect: boolean;
    durationMs: number | null;
  }>;
  providerAttempts: Array<{
    providerId: string;
    status: string;
    durationMs: number;
    fieldsReturned: string[];
    errorCode: string | null;
    errorMessage: string | null;
    metadata: {
      model?: string;
      inputTokens?: number | null;
      outputTokens?: number | null;
      qualityScore?: number;
    } | null;
    createdAt: string;
  }>;
}

export interface RelatedPreview {
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  relation: string;
  translation: string | null;
  partOfSpeech: string | null;
  difference: string | null;
  source: string | null;
  existing: null | {
    id: number;
    term: string;
    initializationStatus: string;
    masteryLevel: string;
    masteryScore: number;
  };
}

export interface RelatedSelection {
  item: RelatedWordItem;
  relation: RelationType;
}
