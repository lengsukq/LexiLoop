import { z } from "zod";
import { MAX_ARTICLE_SELECTED } from "@/lib/config";
import { HOUR_MS } from "@/lib/time";
import {
  IMPORT_MODES,
  INITIALIZATION_FIELDS,
  INITIALIZATION_PROVIDER_IDS,
  PROVIDER_STRATEGIES,
  QUESTION_TYPES,
  REVIEW_RATINGS,
  STUDY_MODES,
} from "@/lib/types";
import { GAME_MODES } from "@/modules/games/modes";
import { PHONETIC_ACCENTS } from "@/modules/phonetics/types";
import { MAX_ACTIVE_ANSWER_DURATION_MS } from "@/modules/reviews/duration";

export const wordInitializeSchema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]).default("FILL_MISSING_FIELDS"),
  requestedFields: z.array(z.enum(INITIALIZATION_FIELDS)).min(1).optional(),
  requestedProviders: z.array(z.enum(INITIALIZATION_PROVIDER_IDS)).min(1).optional(),
  providerStrategy: z.enum(PROVIDER_STRATEGIES).optional(),
}).strict();

export const wordYoudaoPreviewSchema = z.object({
  term: z.string().trim().min(1).max(300).optional(),
}).strict();

export const wordYoudaoApplySchema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]),
  content: z.record(z.string(), z.unknown()),
  newTerm: z.string().trim().min(1).max(300).optional(),
  attempts: z.array(z.object({
    providerId: z.string(),
    status: z.string(),
    durationMs: z.number(),
    fieldsReturned: z.array(z.string()).default([]),
    errorCode: z.string().nullable().default(null),
    errorMessage: z.string().nullable().default(null),
    metadata: z.record(z.string(), z.unknown()).nullable().default(null),
  })).default([]),
}).strict();

export const wordExampleTranslationIndexSchema = z.object({
  index: z.number().int().nonnegative(),
}).strict();

export const studySessionStartSchema = z.object({
  mode: z.enum(STUDY_MODES).default("DAILY"),
  resume: z.boolean().default(true),
  continuous: z.boolean().default(false),
});

export const studyAnswerSchema = z.object({
  clientAnswerId: z.string().min(8).max(128),
  wordId: z.number().int().positive(),
  studySessionId: z.number().int().positive().optional(),
  studySessionItemId: z.number().int().positive().optional(),
  rating: z.enum(REVIEW_RATINGS),
  questionType: z.enum(QUESTION_TYPES),
  userAnswer: z.string().max(1000).optional(),
  durationMs: z.number().int().min(0).max(MAX_ACTIVE_ANSWER_DURATION_MS).optional(),
});

export const studySkipSchema = z.object({
  studySessionId: z.number().int().positive(),
  studySessionItemId: z.number().int().positive(),
  reason: z.enum(["LATER", "NO_AUDIO", "CONTENT_ISSUE"]).default("LATER"),
});

export const reviewPreviewSchema = z.object({
  wordId: z.number().int().positive(),
});

export const initializationPreviewSchema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]).default("FILL_MISSING_FIELDS"),
  onlyMissing: z.boolean().default(true),
  wordIds: z.array(z.number().int().positive()).min(1).max(5000).optional(),
  requestedFields: z.array(z.enum(INITIALIZATION_FIELDS)).min(1),
  requestedProviders: z.array(z.enum(INITIALIZATION_PROVIDER_IDS)).min(1),
  providerStrategy: z.enum(PROVIDER_STRATEGIES).default("PRIORITY_FALLBACK"),
}).strict();

export const initializationBulkSchema = z.object({
  mode: z.enum(["FILL_MISSING_FIELDS", "FORCE_OVERWRITE"]).default("FILL_MISSING_FIELDS"),
  onlyWithoutAi: z.boolean().default(true),
  onlyMissing: z.boolean().optional(),
  wordIds: z.array(z.number().int().positive()).min(1).max(5000).optional(),
  requestedFields: z.array(z.enum(INITIALIZATION_FIELDS)).min(1).optional(),
  requestedProviders: z.array(z.enum(INITIALIZATION_PROVIDER_IDS)).min(1).optional(),
  providerStrategy: z.enum(PROVIDER_STRATEGIES).optional(),
}).strict();

export const initializationRetrySchema = z.union([
  z.object({ jobIds: z.array(z.number().int().positive()).min(1).max(500) }).strict(),
  z.object({ wordIds: z.array(z.number().int().positive()).min(1).max(500) }).strict(),
]);

export const importCommitSchema = z.object({
  previewToken: z.string().uuid(),
  mode: z.enum(IMPORT_MODES),
  resetLearningProgress: z.boolean().default(false),
});

export const articlePreviewSchema = z.object({
  articleText: z.string().min(1).max(60_000),
  sourceLanguage: z.string().trim().min(1).max(20).optional(),
  targetLanguage: z.string().trim().min(1).max(20).optional(),
  examTargets: z.array(z.enum(["CET4", "CET6", "KY", "IELTS", "TOEFL"])).max(5).optional(),
});

export const articleMergeSchema = z.object({
  tokens: z.array(z.string().uuid()).min(1).max(20),
});

const selectedArticleTermSchema = z.union([
  z.string().trim().min(1).max(600),
  z.object({
    term: z.string().trim().min(1).max(600),
    entryType: z.enum(["WORD", "PHRASE", "SENTENCE"]).optional(),
  }),
]);

export const articleCommitSchema = z.object({
  previewToken: z.string().uuid(),
  selectedTerms: z.array(selectedArticleTermSchema).max(MAX_ARTICLE_SELECTED).optional(),
  selectedKeys: z.array(z.string().trim().min(1).max(700)).max(MAX_ARTICLE_SELECTED).optional(),
  mode: z.enum(IMPORT_MODES),
  resetLearningProgress: z.boolean().default(false),
});

export const gameSessionStartSchema = z.object({
  mode: z.enum(GAME_MODES),
});

export const gameSessionCompleteSchema = z.object({
  mode: z.enum(GAME_MODES),
  answers: z.array(z.object({
    itemId: z.number().int().positive(),
    wordId: z.number().int().positive(),
    solved: z.boolean(),
    hadMistake: z.boolean(),
    durationMs: z.number().int().min(0).max(MAX_ACTIVE_ANSWER_DURATION_MS).optional(),
  })).max(20),
  elapsedMs: z.number().int().min(0).max(HOUR_MS),
  mistakeCount: z.number().int().min(0).max(1000),
  maxCombo: z.number().int().min(0).max(1000),
});

export const matchSessionStartSchema = z.object({
  pairCount: z.number().int().min(4).max(8).default(6),
  durationSeconds: z.number().int().min(30).max(180).default(60),
});

export const matchSessionCompleteSchema = z.object({
  results: z.array(z.object({
    itemId: z.number().int().positive(),
    wordId: z.number().int().positive(),
    matched: z.boolean(),
    hadMistake: z.boolean(),
    durationMs: z.number().int().min(0).max(MAX_ACTIVE_ANSWER_DURATION_MS).optional(),
  })).max(8),
  elapsedMs: z.number().int().min(0).max(HOUR_MS),
  durationSeconds: z.number().int().min(30).max(180),
  mistakeCount: z.number().int().min(0).max(1000),
  maxCombo: z.number().int().min(0).max(1000),
});

export const phoneticsSessionStartSchema = z.object({
  accent: z.enum(PHONETIC_ACCENTS),
});

export const phoneticsSessionCompleteSchema = z.object({
  answers: z.array(z.object({
    itemId: z.number().int().positive(),
    wordId: z.number().int().positive(),
    solved: z.boolean(),
    hadMistake: z.boolean(),
    durationMs: z.number().int().min(0).max(MAX_ACTIVE_ANSWER_DURATION_MS).optional(),
  })).max(20),
  elapsedMs: z.number().int().min(0).max(HOUR_MS),
  mistakeCount: z.number().int().min(0).max(1000),
  maxCombo: z.number().int().min(0).max(1000),
});
