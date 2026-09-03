import type { AppSettings, InitializationProviderId, LlmConfig, QuestionTypeConfig } from "@/lib/types";
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
  ai: { enabled: false, providerId: "", model: "", thinkingEnabled: false },
};

export const DEFAULT_QUESTION_TYPE_CONFIG: QuestionTypeConfig = {
  EN_TO_ZH: { enabled: true, weight: 5 },
  EN_TO_ZH_CHOICE: { enabled: true, weight: 5 },
  ZH_TO_EN_CHOICE: { enabled: true, weight: 5 },
  ZH_TO_EN_SPELLING: { enabled: true, weight: 5 },
  LISTENING_SPELLING: { enabled: true, weight: 5 },
  CLOZE_SENTENCE: { enabled: true, weight: 5 },
  LISTENING_CHOICE: { enabled: true, weight: 5 },
  LETTER_BANK: { enabled: true, weight: 5 },
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
  examTargets: [],
  llmConfig: DEFAULT_LLM_CONFIG,
  questionTypeConfig: DEFAULT_QUESTION_TYPE_CONFIG,
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
export const ARTICLE_PHRASE_LIMIT = 15;
export const ARTICLE_SENTENCE_LIMIT = 10;
export const ARTICLE_AI_MAX_OUTPUT_TOKENS = 4500;
export const ARTICLE_SENTENCE_MIN_CHARS = 12;
export const ARTICLE_SNIPPET_CHARS = 8000;
export const ARTICLE_SEGMENT_TARGET_CHARS = 2200;
export const ARTICLE_SEGMENT_MAX_CHARS = 4000;
export const ARTICLE_SEGMENT_CONCURRENCY = 3;
export const ARTICLE_SEGMENT_PREVIEW_CHARS = 120;
export const ARTICLE_SEGMENTS_PER_BATCH_MAX = 10;
export const ARTICLE_DEFAULT_RECOMMENDED_LIMIT = 20;
export const ARTICLE_MAX_SEGMENTS = 20;
export const ARTICLE_MAX_BATCHES = 10;
