import type {
  AppSettings,
  DictionaryContent,
  InitializationField,
  InitializationProviderId,
  LookupInput,
  ProviderAttempt,
} from "@/lib/types";
import type { DictionaryProvider } from "./provider";
import { DictionaryApiProvider } from "./providers/dictionary-api";
import { EcdictProvider } from "./providers/ecdict";
import { MyMemoryProvider } from "./providers/mymemory";
import { AiLexicalProvider } from "./providers/ai-lexical";
import { MerriamWebsterProvider } from "./providers/merriam-webster";
import { mergeDictionaryContent } from "./content";
import {
  fieldsReturned,
  normalizeRequestedFields,
  projectDictionaryContent,
  requestedFieldStatus,
} from "./selection";

export const PROVIDER_CAPABILITIES: Record<InitializationProviderId, InitializationField[]> = {
  "merriam-webster": ["definitions", "pronunciations.phonetic", "pronunciations.audio", "examples", "synonyms", "antonyms"],
  "dictionaryapi.dev": ["definitions", "pronunciations.phonetic", "pronunciations.audio", "examples", "synonyms", "antonyms"],
  ecdict: ["definitions", "pronunciations.phonetic", "pronunciations.audio", "forms", "tags"],
  ai: ["definitions", "examples", "phrases", "forms", "synonyms", "antonyms", "wordFamily", "confusedWords", "roots", "affixes", "tags", "summary", "learning", "sentenceAnalysis"],
  mymemory: ["definitions"],
};

function providerKey(provider: DictionaryProvider): InitializationProviderId {
  return provider.id.startsWith("ai:") ? "ai" : provider.id as InitializationProviderId;
}

function createProvider(id: InitializationProviderId, settings: AppSettings): DictionaryProvider | null {
  if (id === "merriam-webster") return settings.merriamWebsterEnabled ? new MerriamWebsterProvider(settings) : null;
  if (id === "dictionaryapi.dev") return settings.dictionaryApiEnabled ? new DictionaryApiProvider() : null;
  if (id === "ecdict") return settings.ecdictEnabled ? new EcdictProvider() : null;
  if (id === "ai") return settings.llmConfig.purposes.IMPORT_ENRICHMENT.enabled ? new AiLexicalProvider(settings) : null;
  if (id === "mymemory") return settings.myMemoryEnabled ? new MyMemoryProvider() : null;
  return null;
}

function providersFor(settings: AppSettings, selected?: InitializationProviderId[]): DictionaryProvider[] {
  const defaultOrder: InitializationProviderId[] = settings.llmConfig.purposes.IMPORT_ENRICHMENT.enabled
    ? ["merriam-webster", "ai", "dictionaryapi.dev", "ecdict"]
    : ["merriam-webster", "dictionaryapi.dev", "ecdict", "mymemory"];
  const order = selected?.length ? [...new Set(selected)] : defaultOrder;
  return order.map((id) => createProvider(id, settings)).filter((provider): provider is DictionaryProvider => Boolean(provider));
}

function supportsRequestedFields(provider: DictionaryProvider, requestedFields: InitializationField[]): boolean {
  if (!requestedFields.length) return true;
  const capabilities = PROVIDER_CAPABILITIES[providerKey(provider)];
  return requestedFields.some((field) => capabilities.includes(field));
}

type SettledProvider = {
  content: DictionaryContent | null;
  attempt: ProviderAttempt;
  transient: boolean;
};

async function runProvider(provider: DictionaryProvider, input: LookupInput, requestedFields: InitializationField[]): Promise<SettledProvider> {
  const started = Date.now();
  try {
    const result = await provider.lookup(input);
    const projected = result.content ? projectDictionaryContent(result.content, requestedFields) : null;
    const returned = projected ? fieldsReturned(projected, requestedFields) : [];
    const hasContent = returned.length > 0 || (!requestedFields.length && Boolean(result.content));
    const attempt: ProviderAttempt = {
      providerId: provider.id,
      status: hasContent ? "SUCCESS" : !result.errorCode || result.errorCode === "NOT_FOUND" || result.errorCode === "EMPTY_RESULT" ? "EMPTY" : "FAILED",
      durationMs: Date.now() - started,
      fieldsReturned: returned,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      metadata: result.metadata,
    };
    return { content: hasContent ? projected : null, attempt, transient: Boolean(result.transient) };
  } catch (error) {
    return {
      content: null,
      attempt: { providerId: provider.id, status: "FAILED", durationMs: Date.now() - started, fieldsReturned: [], errorCode: "EXCEPTION", errorMessage: String(error) },
      transient: true,
    };
  }
}

export async function lookupDictionary(input: LookupInput, settings: AppSettings): Promise<{
  content: DictionaryContent;
  attempts: ProviderAttempt[];
  hasTransientFailure: boolean;
  contentSource: "AI_ONLY" | "MIXED" | "DICTIONARY_ONLY";
  requiredProviderFailure: null | { transient: boolean; errorCode: string; errorMessage: string };
}> {
  const requestedFields = normalizeRequestedFields(input.requestedFields);
  const providers = providersFor(settings, input.requestedProviders)
    .filter((provider) => provider.supports(input) && supportsRequestedFields(provider, requestedFields));

  let settled: SettledProvider[];
  if (input.providerStrategy === "PRIORITY_FALLBACK") {
    settled = [];
    let accumulated = mergeDictionaryContent();
    for (const provider of providers) {
      const result = await runProvider(provider, input, requestedFields);
      settled.push(result);
      if (result.content) accumulated = mergeDictionaryContent(accumulated, result.content);
      const satisfied = requestedFields.length
        ? requestedFieldStatus(accumulated, requestedFields) === "READY"
        : accumulated.definitions.length > 0;
      if (satisfied) break;
    }
  } else {
    settled = await Promise.all(providers.map((provider) => runProvider(provider, input, requestedFields)));
  }

  const content = mergeDictionaryContent(...settled.map((item) => item.content));
  const aiResult = settled.find((item) => item.attempt.providerId.startsWith("ai:"));
  const implicitFullAiJob = !input.requestedFields?.length && !input.requestedProviders?.length
    && settings.llmConfig.purposes.IMPORT_ENRICHMENT.enabled;
  const requiredProviderFailure = implicitFullAiJob && aiResult?.attempt.status !== "SUCCESS"
    ? {
        transient: aiResult?.transient ?? false,
        errorCode: aiResult?.attempt.errorCode ?? "AI_PROVIDER_MISSING",
        errorMessage: aiResult?.attempt.errorMessage ?? "AI 词条初始化 Provider 未执行成功。",
      }
    : null;
  const aiSuccess = aiResult?.attempt.status === "SUCCESS";
  const nonAiSuccess = settled.some((item) => !item.attempt.providerId.startsWith("ai:") && item.attempt.status === "SUCCESS");
  const contentSource = aiSuccess && !nonAiSuccess ? "AI_ONLY" as const : aiSuccess ? "MIXED" as const : "DICTIONARY_ONLY" as const;
  return {
    content,
    attempts: settled.map((item) => item.attempt),
    hasTransientFailure: settled.some((item) => item.transient),
    contentSource,
    requiredProviderFailure,
  };
}
