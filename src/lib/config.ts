import type { AppSettings, LlmConfig } from "@/lib/types";

export const DEFAULT_LLM_CONFIG: LlmConfig = {
  providers: {
    openai: { apiKey: "", baseUrl: "https://api.openai.com/v1" },
    anthropic: { apiKey: "", baseUrl: "https://api.anthropic.com/v1" },
    siliconflow: { apiKey: "", baseUrl: "https://api.siliconflow.cn/v1" },
    custom: { apiKey: "", baseUrl: "" },
  },
  purposes: {
    TTS: { enabled: false, providerId: "siliconflow", model: "TeleAI/TeleSpeechASR" },
    IMPORT_ENRICHMENT: { enabled: false, providerId: "openai", model: "gpt-4o-mini", temperature: 0.2, maxOutputTokens: 3200, timeoutMs: 60000 },
    STUDY_PLAN: { enabled: false, providerId: "openai", model: "gpt-4o-mini" },
    SUGGESTION: { enabled: false, providerId: "openai", model: "gpt-4o-mini" },
  },
};

export const DEFAULT_SETTINGS: AppSettings = {
  dailyNewWords: 10,
  dailyWrongWordLimit: 10,
  dailyDueReviewLimit: 30,
  targetRetentionRate: 0.9,
  defaultAccent: "US",
  playbackSpeed: 1,
  autoPlayPronunciation: true,
  dictionaryApiEnabled: process.env.DICTIONARY_API_ENABLED !== "false",
  myMemoryEnabled: process.env.MYMEMORY_ENABLED !== "false",
  ecdictEnabled: process.env.ECDICT_ENABLED === "true",
  llmConfig: DEFAULT_LLM_CONFIG,
};

export const IMPORT_PREVIEW_TTL_MS = 30 * 60 * 1000;
export const MAX_CSV_BYTES = 10 * 1024 * 1024;
export const MAX_CSV_ROWS = 20_000;
export const WORKER_STALE_AFTER_MS = Number(process.env.WORKER_STALE_AFTER_MS ?? 30_000);
