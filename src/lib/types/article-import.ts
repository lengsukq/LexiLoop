import type { EntryType } from "./core";

export interface ArticleCandidate {
  term: string;
  normalizedTerm: string;
  occurrences: number;
  status: "CANDIDATE" | "KNOWN" | "TOO_COMMON";
  aiReason?: string | null;
  difficulty?: number | null;
  cefrLevel?: string | null;
  frequency?: string | null;
}

export interface ArticleStats {
  charCount: number;
  wordCount: number;
  uniqueCount: number;
  knownCount: number;
  unknownCount: number;
}

export interface ArticleImportPreview {
  previewToken: string;
  filename: string;
  articleStats: ArticleStats;
  candidates: ArticleCandidate[];
  /** Subset recommended by AI; when AI is unavailable equals all CANDIDATE terms. */
  recommendedTerms: string[];
  aiApplied: boolean;
  aiError?: string | null;
  totalCandidates: number;
  knownCount: number;
  expiresAt: string;
}
