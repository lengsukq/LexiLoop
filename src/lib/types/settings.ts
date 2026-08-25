import type { InitializationProviderId } from "./core";

export const VOCABULARY_LEVELS = ["AUTO", "CET4", "CET6", "KY", "IELTS", "TOEFL"] as const;
export type VocabularyLevel = (typeof VOCABULARY_LEVELS)[number];

export interface AppSettings {
  dailyNewWords: number; dailyWrongWordLimit: number; dailyDueReviewLimit: number; targetRetentionRate: number; choiceRevealDelaySeconds: number;
  defaultAccent: "US" | "UK"; wordSpeed: number; phraseSpeed: number; sentenceSpeed: number; autoPlayPronunciation: boolean;
  dictionaryApiEnabled: boolean; myMemoryEnabled: boolean; merriamWebsterEnabled: boolean;
  merriamWebsterDictionaryKey: string; merriamWebsterThesaurusKey: string; backgroundConcurrency: number; aiRetryCount: number;
  tencentTranslateEnabled: boolean; tencentTranslateSecretId: string; tencentTranslateSecretKey: string; tencentTranslateProjectId: number;
  youdaoEnabled: boolean; icibaEnabled: boolean; translationProviderOrder: InitializationProviderId[]; llmConfig: LlmConfig;
  vocabularyLevel: VocabularyLevel;
}

export const LLM_PURPOSE_IDS = ["TTS", "IMPORT_ENRICHMENT", "STUDY_PLAN", "SUGGESTION"] as const;
export type LlmPurposeId = (typeof LLM_PURPOSE_IDS)[number];
export interface LlmProviderConfig {
  id: string; name: string; apiType: "openai" | "anthropic"; baseUrl: string; apiKey: string; models?: string[]; defaultModel?: string;
}
export interface LlmPurposeConfig {
  enabled: boolean; providerId: string; model: string; retryProviderId?: string; retryModel?: string;
  temperature?: number; maxOutputTokens?: number; timeoutMs?: number;
  thinkingEnabled?: boolean;
  thinkingBudgetTokens?: number;
  reasoningEffort?: "minimal" | "low" | "medium" | "high";
}
export interface LlmConfig { providers: LlmProviderConfig[]; purposes: Record<LlmPurposeId, LlmPurposeConfig>; }
