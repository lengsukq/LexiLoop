import type { AppSettings, InitializationProviderId, LlmConfig } from "@/lib/types";
import { MINUTE_MS } from "@/lib/time";

export const DEFAULT_LLM_CONFIG: LlmConfig = {
  providers: [
    {
      id: "opencode-zen",
      name: "OpenCode Zen",
      apiType: "openai",
      baseUrl: "https://opencode.ai/zen/v1",
      apiKey: "public",
      models: [],
      defaultModel: "",
    },
  ],
  purposes: {
    TTS: { enabled: false, providerId: "", model: "", thinkingEnabled: false },
    IMPORT_ENRICHMENT: { enabled: false, providerId: "", model: "", thinkingEnabled: false },
    STUDY_PLAN: { enabled: false, providerId: "", model: "", thinkingEnabled: false },
    SUGGESTION: { enabled: false, providerId: "", model: "", thinkingEnabled: false },
  },
};

export const DEFAULT_SETTINGS: AppSettings = {
  dailyNewWords: 10,
  dailyWrongWordLimit: 10,
  dailyDueReviewLimit: 30,
  targetRetentionRate: 0.9,
  choiceRevealDelaySeconds: 2,
  defaultAccent: "US",
  wordSpeed: 1,
  phraseSpeed: 1,
  sentenceSpeed: 1,
  autoPlayPronunciation: true,
  dictionaryApiEnabled: true,
  myMemoryEnabled: true,
  merriamWebsterEnabled: false,
  merriamWebsterDictionaryKey: "",
  merriamWebsterThesaurusKey: "",
  backgroundConcurrency: 2,
  aiRetryCount: 1,
  tencentTranslateEnabled: false,
  tencentTranslateSecretId: "",
  tencentTranslateSecretKey: "",
  tencentTranslateProjectId: 0,
  youdaoEnabled: true,
  icibaEnabled: true,
  translationProviderOrder: ["youdao", "iciba", "merriam-webster", "dictionaryapi.dev", "tencent-translate", "mymemory"] as InitializationProviderId[],
  vocabularyLevel: "AUTO",
  llmConfig: DEFAULT_LLM_CONFIG,
};

export const IMPORT_PREVIEW_TTL_MS = 30 * MINUTE_MS;
export const MAX_CSV_BYTES = 10 * 1024 * 1024;
export const MAX_CSV_ROWS = 20_000;
export const WORKER_STALE_AFTER_MS = 30_000;
export const MAX_ARTICLE_CHARS = 50_000;
export const MIN_ARTICLE_CHARS = 20;
export const MAX_ARTICLE_CANDIDATES = 200;
export const MAX_ARTICLE_SELECTED = 100;
export const ARTICLE_AI_CANDIDATE_LIMIT = 80;
export const ARTICLE_SNIPPET_CHARS = 8000;
