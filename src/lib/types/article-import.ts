export type ArticleCandidateKind = "WORD" | "PHRASE" | "SENTENCE";
export interface ArticleKeyVocab { term: string; pos: string | null; meaning: string; }
export interface ArticleAiCard {
  literalTranslation: string | null;
  freeTranslation: string | null;
  keyVocab: ArticleKeyVocab[];
  grammarPattern: string | null;
  grammarNotes: string[];
  nuance: string | null;
}
export interface ArticleCandidate {
  term: string;
  normalizedTerm: string;
  occurrences: number;
  status: "CANDIDATE" | "KNOWN" | "TOO_COMMON";
  entryType: ArticleCandidateKind;
  sourceSentence?: string | null;
  aiReason?: string | null;
  difficulty?: number | null;
  cefrLevel?: string | null;
  frequency?: string | null;
  aiCard?: ArticleAiCard | null;
}
export interface ArticleStats {
  charCount: number;
  wordCount: number;
  uniqueCount: number;
  knownCount: number;
  unknownCount: number;
  phraseCount: number;
  sentenceCount: number;
}
export interface ArticleImportPreview {
  previewToken: string;
  filename: string;
  articleStats: ArticleStats;
  candidates: ArticleCandidate[];
  recommendedTerms: string[];
  /** Composite keys entryType\0normalizedTerm for selection without collision. */
  recommendedKeys: string[];
  aiApplied: boolean;
  aiError?: string | null;
  totalCandidates: number;
  knownCount: number;
  expiresAt: string;
}

export type ArticleSegmentStatus = "idle" | "loading" | "success" | "error";
export interface ArticleSegment {
  id: string;
  index: number;
  text: string;
  charCount: number;
  status: ArticleSegmentStatus;
  preview?: ArticleImportPreview;
  error?: string | null;
  previewToken?: string | null;
}

