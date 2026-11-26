import type { EntryType, InitializationField, InitializationMode, InitializationProviderId, ProviderStrategy } from "./core";

export type UsageRegister = "FORMAL" | "INFORMAL" | "NEUTRAL" | "SLANG";
export type ContentDifficulty = "EASY" | "NORMAL" | "ADVANCED";

export interface DefinitionItem {
  language: string; partOfSpeech: string | null; text: string; source: string; isUserEdited: boolean;
  senseId?: string; register?: UsageRegister | null; usageNote?: string | null;
}
export interface PronunciationItem {
  accent: "US" | "UK"; phonetic: string | null; audioUrl: string | null; source: string; isSynthetic: boolean;
}
export interface ExampleItem {
  sentence: string; translation: string | null; source: string; isUserAdded: boolean;
  senseId?: string; difficulty?: ContentDifficulty;
}
export interface PhraseItem {
  phrase: string; translation: string | null; source: string;
  kind?: "COLLOCATION" | "PHRASE" | "IDIOM"; senseId?: string; example?: string | null;
}
export interface WordFormItem {
  type: "LEMMA" | "PAST" | "PAST_PARTICIPLE" | "PRESENT_PARTICIPLE" | "THIRD_PERSON" | "PLURAL" | "COMPARATIVE" | "SUPERLATIVE" | "OTHER";
  value: string; source: string;
}
export interface RelatedWordItem {
  word: string; translation: string | null; partOfSpeech: string | null; relation: string; source: string; difference?: string | null;
}
export interface RootItem { root: string; meaning: string; origin: string | null; source: string; }
export interface AffixItem { value: string; type: "PREFIX" | "SUFFIX"; meaning: string; source: string; }
export interface LexicalSummary {
  shortDefinition: string | null; translation: string | null;
  cefrLevel: "A1" | "A2" | "B1" | "B2" | "C1" | "C2" | null;
  frequency: "VERY_COMMON" | "COMMON" | "NORMAL" | "RARE" | null;
}
export interface LearningContent { pronunciationTip: string | null; mnemonic: string | null; commonMistakes: string[]; }
export interface SentenceExpressionItem { expression: string; meaning: string; note: string | null; }
export interface SentenceVariationItem { sentence: string; translation: string | null; }
export interface SentenceGrammarExampleItem { sentence: string; translation: string; focus: string | null; }
export interface SentenceAnalysis {
  grammarPattern: string | null; grammarExplanation: string | null; grammarNotes: string[];
  keyExpressions: SentenceExpressionItem[]; similarExamples: SentenceGrammarExampleItem[]; variations: SentenceVariationItem[];
}

export interface DictionaryContent {
  definitions: DefinitionItem[]; pronunciations: PronunciationItem[]; examples: ExampleItem[]; phrases: PhraseItem[]; forms: WordFormItem[];
  synonyms: RelatedWordItem[]; antonyms: RelatedWordItem[]; wordFamily: RelatedWordItem[]; confusedWords: RelatedWordItem[];
  roots: RootItem[]; affixes: AffixItem[]; summary: LexicalSummary; learning: LearningContent; sentenceAnalysis: SentenceAnalysis; tags: string[];
}

export interface ProviderAttempt {
  providerId: string; status: "SUCCESS" | "EMPTY" | "FAILED"; durationMs: number; fieldsReturned: string[];
  errorCode?: string; errorMessage?: string;
  metadata?: {
    model?: string; promptVersion?: string; schemaVersion?: number; inputTokens?: number | null; outputTokens?: number | null;
    qualityScore?: number; finishReason?: string | null; rawResponse?: string; sourceEndpoint?: string; fallbackUsed?: boolean;
    endpointAttempts?: Array<{ endpoint: string; status: "SUCCESS" | "EMPTY" | "FAILED"; statusCode?: number; errorCode?: string; errorMessage?: string }>;
  };
}

export interface LookupInput {
  term: string; normalizedTerm: string; entryType: EntryType; sourceLanguage: string; targetLanguage: string;
  initializationMode?: InitializationMode; requestedFields?: InitializationField[]; requestedProviders?: InitializationProviderId[];
  providerStrategy?: ProviderStrategy; existingContent?: DictionaryContent;
}
