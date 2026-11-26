import type { DictionaryContent, LookupInput, ProviderAttempt } from "@/lib/types";

export interface ProviderResult {
  content: Partial<DictionaryContent> | null;
  errorCode?: string;
  errorMessage?: string;
  transient?: boolean;
  metadata?: ProviderAttempt["metadata"];
}

export interface DictionaryProvider {
  id: string;
  supports(input: LookupInput): boolean;
  lookup(input: LookupInput): Promise<ProviderResult>;
}
