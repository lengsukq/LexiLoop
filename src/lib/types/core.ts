export const INITIALIZATION_STATUSES = [
  "PENDING", "QUEUED", "RUNNING", "READY", "PARTIAL", "FAILED", "DISABLED",
] as const;
export type InitializationStatus = (typeof INITIALIZATION_STATUSES)[number];

export const INITIALIZATION_MODES = ["SKIP_INITIALIZED", "FILL_MISSING_FIELDS", "FORCE_OVERWRITE"] as const;
export type InitializationMode = (typeof INITIALIZATION_MODES)[number];

export const INITIALIZATION_FIELDS = [
  "definitions", "pronunciations.phonetic", "pronunciations.audio", "examples", "phrases", "forms",
  "synonyms", "antonyms", "wordFamily", "confusedWords", "roots", "affixes", "tags", "summary", "learning", "sentenceAnalysis",
] as const;
export type InitializationField = (typeof INITIALIZATION_FIELDS)[number];

export const INITIALIZATION_PROVIDER_IDS = [
  "merriam-webster", "dictionaryapi.dev", "ai", "mymemory", "tencent-translate", "youdao", "iciba",
] as const;
export type InitializationProviderId = (typeof INITIALIZATION_PROVIDER_IDS)[number];

export const PROVIDER_STRATEGIES = ["PARALLEL_MERGE", "PRIORITY_FALLBACK"] as const;
export type ProviderStrategy = (typeof PROVIDER_STRATEGIES)[number];

export interface InitializationTaskOptions {
  requestedFields?: InitializationField[];
  requestedProviders?: InitializationProviderId[];
  providerStrategy?: ProviderStrategy;
}

export const AI_TASK_TYPES = ["INITIALIZE", "MNEMONIC", "EXAMPLE_TRANSLATIONS"] as const;
export type AiTaskType = (typeof AI_TASK_TYPES)[number];
export const IMPORT_MODES = ["SKIP_EXISTING", "FILL_MISSING", "FORCE_DICTIONARY_REFRESH"] as const;
export type ImportMode = (typeof IMPORT_MODES)[number];
export const MASTERY_LEVELS = ["NEW", "LEARNING", "FAMILIAR", "PROFICIENT", "MASTERED"] as const;
export type MasteryLevel = (typeof MASTERY_LEVELS)[number];
export const REVIEW_RATINGS = ["AGAIN", "HARD", "GOOD", "EASY"] as const;
export type ReviewRating = (typeof REVIEW_RATINGS)[number];
export const STUDY_MODES = ["DAILY", "NEW_WORDS", "DUE_REVIEW", "WRONG_WORDS", "LISTENING", "SPELLING", "SENTENCE_REVIEW", "AI_RECOMMENDED"] as const;
export type StudyMode = (typeof STUDY_MODES)[number];
export const QUESTION_TYPES = ["EN_TO_ZH", "EN_TO_ZH_CHOICE", "ZH_TO_EN_CHOICE", "ZH_TO_EN_SPELLING", "LISTENING_SPELLING"] as const;
export type QuestionType = (typeof QUESTION_TYPES)[number];
export const ENTRY_TYPES = ["WORD", "PHRASE", "SENTENCE"] as const;
export type EntryType = (typeof ENTRY_TYPES)[number];

export interface TopScoreEntry {
  score: number;
  maxCombo: number;
  accuracy: number;
  elapsedMs: number;
  playedAt: number;
  isCurrent: boolean;
}

export interface LeaderboardSummary {
  rank: number;
  inTop10: boolean;
  isNewBest: boolean;
  best: number;
  top: TopScoreEntry[];
}
