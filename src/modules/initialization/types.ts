import type {
  AiTaskType,
  InitializationField,
  InitializationMode,
  InitializationProviderId,
  ProviderStrategy,
} from "@/lib/types";

export interface ClaimedJob {
  id: number;
  wordId: number;
  taskType: AiTaskType;
  mode: InitializationMode;
  attemptCount: number;
  maxAttempts: number;
  requestedFields?: InitializationField[];
  requestedProviders?: InitializationProviderId[];
  providerStrategy?: ProviderStrategy;
}
