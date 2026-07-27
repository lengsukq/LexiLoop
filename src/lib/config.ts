import type { AppSettings, LlmConfig } from "@/lib/types";

export const DEFAULT_LLM_CONFIG: LlmConfig = {
  providers: [
    {
      id: "opencode-zen",
      name: "OpenCode Zen",
      apiType: "openai",
      baseUrl: "https://opencode.ai/zen/v1",
      apiKey: "public",
    },
  ],
  purposes: {
    TTS: { enabled: false, providerId: "", model: "" },
    IMPORT_ENRICHMENT: { enabled: true, providerId: "opencode-zen", model: "deepseek-v4-flash-free" },
    STUDY_PLAN: { enabled: true, providerId: "opencode-zen", model: "deepseek-v4-flash-free" },
    SUGGESTION: { enabled: false, providerId: "opencode-zen", model: "mimo-v2.5-free" },
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
