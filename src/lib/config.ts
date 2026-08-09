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
    TTS: { enabled: false, providerId: "", model: "" },
    IMPORT_ENRICHMENT: { enabled: false, providerId: "", model: "" },
    STUDY_PLAN: { enabled: false, providerId: "", model: "" },
    SUGGESTION: { enabled: false, providerId: "", model: "" },
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
  translationProviderOrder: ["youdao", "merriam-webster", "dictionaryapi.dev", "tencent-translate", "mymemory"] as InitializationProviderId[],
  llmConfig: DEFAULT_LLM_CONFIG,
};

export const IMPORT_PREVIEW_TTL_MS = 30 * MINUTE_MS;
export const MAX_CSV_BYTES = 10 * 1024 * 1024;
export const MAX_CSV_ROWS = 20_000;
export const WORKER_STALE_AFTER_MS = 30_000;
