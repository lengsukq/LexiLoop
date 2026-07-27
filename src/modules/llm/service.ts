import type { LlmProviderId, LlmPurposeId } from "@/lib/types";

export const LLM_PROVIDER_META: Record<
  LlmProviderId,
  {
    name: string;
    suggestedModels: Partial<Record<LlmPurposeId, string[]>>;
  }
> = {
  openai: {
    name: "OpenAI",
    suggestedModels: {
      TTS: ["tts-1", "tts-1-hd"],
      IMPORT_ENRICHMENT: ["gpt-4o-mini", "gpt-4o"],
      STUDY_PLAN: ["gpt-4o-mini", "gpt-4o"],
      SUGGESTION: ["gpt-4o-mini", "gpt-4o"],
    },
  },
  anthropic: {
    name: "Anthropic",
    suggestedModels: {
      IMPORT_ENRICHMENT: ["claude-3-5-haiku", "claude-3-5-sonnet"],
      STUDY_PLAN: ["claude-3-5-haiku", "claude-3-5-sonnet"],
      SUGGESTION: ["claude-3-5-haiku", "claude-3-5-sonnet"],
    },
  },
  siliconflow: {
    name: "SiliconFlow",
    suggestedModels: {
      TTS: ["TeleAI/TeleSpeechASR"],
      IMPORT_ENRICHMENT: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"],
      STUDY_PLAN: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"],
      SUGGESTION: ["Qwen/Qwen2.5-7B-Instruct", "deepseek-ai/DeepSeek-V3"],
    },
  },
  custom: {
    name: "自定义",
    suggestedModels: {},
  },
};

export type { LlmProviderId, LlmPurposeId, LlmConfig, LlmProviderConfig, LlmPurposeConfig } from "@/lib/types";
