export const INITIALIZATION_STATUSES = [
  "PENDING",
  "QUEUED",
  "RUNNING",
  "READY",
  "PARTIAL",
  "FAILED",
  "DISABLED",
] as const;
export type InitializationStatus = (typeof INITIALIZATION_STATUSES)[number];

export const INITIALIZATION_MODES = [
  "SKIP_INITIALIZED",
  "FILL_MISSING_FIELDS",
  "FORCE_OVERWRITE",
] as const;
export type InitializationMode = (typeof INITIALIZATION_MODES)[number];

export const IMPORT_MODES = [
  "SKIP_EXISTING",
  "FILL_MISSING",
  "FORCE_DICTIONARY_REFRESH",
] as const;
export type ImportMode = (typeof IMPORT_MODES)[number];

export const MASTERY_LEVELS = ["NEW", "LEARNING", "FAMILIAR", "PROFICIENT", "MASTERED"] as const;
export type MasteryLevel = (typeof MASTERY_LEVELS)[number];

export const REVIEW_RATINGS = ["AGAIN", "HARD", "GOOD", "EASY"] as const;
export type ReviewRating = (typeof REVIEW_RATINGS)[number];

export const STUDY_MODES = ["DAILY", "NEW_WORDS", "DUE_REVIEW", "WRONG_WORDS", "LISTENING", "SPELLING"] as const;
export type StudyMode = (typeof STUDY_MODES)[number];

export const QUESTION_TYPES = ["EN_TO_ZH", "EN_TO_ZH_CHOICE", "ZH_TO_EN_SPELLING", "LISTENING_SPELLING"] as const;
export type QuestionType = (typeof QUESTION_TYPES)[number];

export const ENTRY_TYPES = ["WORD", "PHRASE", "SENTENCE"] as const;
export type EntryType = (typeof ENTRY_TYPES)[number];

export type UsageRegister = "FORMAL" | "INFORMAL" | "NEUTRAL" | "SLANG";
export type ContentDifficulty = "EASY" | "NORMAL" | "ADVANCED";

export interface DefinitionItem {
  language: string;
  partOfSpeech: string | null;
  text: string;
  source: string;
  isUserEdited: boolean;
  senseId?: string;
  register?: UsageRegister | null;
  usageNote?: string | null;
}

export interface PronunciationItem {
  accent: "US" | "UK" | "GENERAL";
  phonetic: string | null;
  audioUrl: string | null;
  source: string;
  isSynthetic: boolean;
}

export interface ExampleItem {
  sentence: string;
  translation: string | null;
  source: string;
  isUserAdded: boolean;
  senseId?: string;
  difficulty?: ContentDifficulty;
}

export interface PhraseItem {
  phrase: string;
  translation: string | null;
  source: string;
  kind?: "COLLOCATION" | "PHRASE" | "IDIOM";
  senseId?: string;
  example?: string | null;
}

export interface WordFormItem {
  type: "LEMMA" | "PAST" | "PAST_PARTICIPLE" | "PRESENT_PARTICIPLE" | "THIRD_PERSON" | "PLURAL" | "COMPARATIVE" | "SUPERLATIVE" | "OTHER";
  value: string;
  source: string;
}

export interface RelatedWordItem {
  word: string;
  translation: string | null;
  partOfSpeech: string | null;
  relation: string;
  source: string;
  difference?: string | null;
}

export interface RootItem {
  root: string;
  meaning: string;
  origin: string | null;
  source: string;
}

export interface AffixItem {
  value: string;
  type: "PREFIX" | "SUFFIX";
  meaning: string;
  source: string;
}

export interface LexicalSummary {
  shortDefinition: string | null;
  translation: string | null;
  cefrLevel: "A1" | "A2" | "B1" | "B2" | "C1" | "C2" | null;
  frequency: "VERY_COMMON" | "COMMON" | "NORMAL" | "RARE" | null;
}

export interface LearningContent {
  pronunciationTip: string | null;
  mnemonic: string | null;
  commonMistakes: string[];
}

export interface SentenceExpressionItem {
  expression: string;
  meaning: string;
  note: string | null;
}

export interface SentenceVariationItem {
  sentence: string;
  translation: string | null;
}

export interface SentenceAnalysis {
  grammarNotes: string[];
  keyExpressions: SentenceExpressionItem[];
  variations: SentenceVariationItem[];
}

export interface DictionaryContent {
  definitions: DefinitionItem[];
  pronunciations: PronunciationItem[];
  examples: ExampleItem[];
  phrases: PhraseItem[];
  forms: WordFormItem[];
  synonyms: RelatedWordItem[];
  antonyms: RelatedWordItem[];
  wordFamily: RelatedWordItem[];
  confusedWords: RelatedWordItem[];
  roots: RootItem[];
  affixes: AffixItem[];
  summary: LexicalSummary;
  learning: LearningContent;
  sentenceAnalysis: SentenceAnalysis;
  tags: string[];
}

export interface ProviderAttempt {
  providerId: string;
  status: "SUCCESS" | "EMPTY" | "FAILED";
  durationMs: number;
  fieldsReturned: string[];
  errorCode?: string;
  errorMessage?: string;
  metadata?: {
    model?: string;
    promptVersion?: string;
    schemaVersion?: number;
    inputTokens?: number | null;
    outputTokens?: number | null;
    qualityScore?: number;
    finishReason?: string | null;
    rawResponse?: string;
  };
}

export interface LookupInput {
  term: string;
  normalizedTerm: string;
  entryType: EntryType;
  sourceLanguage: string;
  targetLanguage: string;
  initializationMode?: InitializationMode;
  requestedFields?: string[];
  existingContent?: DictionaryContent;
}

export interface AppSettings {
  dailyNewWords: number;
  dailyWrongWordLimit: number;
  dailyDueReviewLimit: number;
  targetRetentionRate: number;
  defaultAccent: "US" | "UK" | "GENERAL";
  playbackSpeed: number;
  autoPlayPronunciation: boolean;
  dictionaryApiEnabled: boolean;
  myMemoryEnabled: boolean;
  ecdictEnabled: boolean;
  backgroundConcurrency: number;
  llmConfig: LlmConfig;
}

export const LLM_PURPOSE_IDS = ["TTS", "IMPORT_ENRICHMENT", "STUDY_PLAN", "SUGGESTION"] as const;
export type LlmPurposeId = (typeof LLM_PURPOSE_IDS)[number];

export interface LlmProviderConfig {
  id: string;
  name: string;
  apiType: "openai" | "anthropic";
  baseUrl: string;
  apiKey: string;
}

export interface LlmPurposeConfig {
  enabled: boolean;
  providerId: string;
  model: string;
  temperature?: number;
  maxOutputTokens?: number;
  timeoutMs?: number;
}

export interface LlmConfig {
  providers: LlmProviderConfig[];
  purposes: Record<LlmPurposeId, LlmPurposeConfig>;
}

export interface ImportPreviewRow {
  rowNumber: number;
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  sourceLanguageName: string;
  targetLanguageName: string;
  entryType: EntryType;
  sourceCreatedAt: string | null;
  status: "NEW" | "EXISTING" | "DUPLICATE" | "INVALID";
  errors: string[];
}

export interface ImportPreview {
  previewToken: string;
  filename: string;
  totalRows: number;
  validRows: number;
  invalidRows: number;
  duplicateRows: number;
  newRows: number;
  existingRows: number;
  languages: Record<string, number>;
  entryTypes: Record<string, number>;
  rows: ImportPreviewRow[];
  expiresAt: string;
}

export interface ManualContentPreview {
  previewToken: string;
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  sourceLanguageName: string;
  targetLanguageName: string;
  contentType: EntryType;
  content: DictionaryContent;
  providerAttempts: ProviderAttempt[];
  existingWordId: number | null;
  expiresAt: string;
}

export interface StudyItemView {
  itemId: number;
  position: number;
  taskType: "NEW" | "REVIEW" | "WRONG" | "LISTENING" | "SPELLING";
  questionType: QuestionType;
  choices?: string[];
  word: {
    id: number;
    term: string;
    sourceLanguage: string;
    targetLanguage: string;
    entryType: EntryType;
    content: DictionaryContent;
  };
}
