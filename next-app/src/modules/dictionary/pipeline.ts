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
import { MyMemoryProvider } from "./providers/mymemory";
import { AiLexicalProvider } from "./providers/ai-lexical";
import { YoudaoProvider } from "./providers/youdao";
import { IcibaProvider } from "./providers/iciba";
import { MerriamWebsterProvider } from "./providers/merriam-webster";
import { TencentTranslateProvider } from "./providers/tencent-translate";
import { contentStatus, mergeDictionaryContent } from "./content";
import {
  fieldsReturned,
  normalizeRequestedFields,
  projectDictionaryContent,
  requestedFieldStatusForLanguages,
} from "./selection";

export const PROVIDER_CAPABILITIES: Record<InitializationProviderId, InitializationField[]> = {
  "merriam-webster": ["definitions", "pronunciations.phonetic", "pronunciations.audio", "examples", "synonyms", "antonyms"],
  "dictionaryapi.dev": ["definitions", "pronunciations.phonetic", "pronunciations.audio", "examples", "synonyms", "antonyms"],
  youdao: ["definitions", "pronunciations.phonetic", "pronunciations.audio", "examples", "phrases", "forms", "synonyms", "antonyms", "wordFamily", "roots", "affixes", "summary", "tags"],
  iciba: ["definitions", "pronunciations.phonetic", "pronunciations.audio", "examples", "phrases", "forms", "synonyms", "antonyms", "wordFamily", "roots", "affixes", "summary", "tags"],
  ai: ["definitions", "examples", "phrases", "forms", "synonyms", "antonyms", "wordFamily", "confusedWords", "roots", "affixes", "tags", "summary", "learning", "sentenceAnalysis"],
  mymemory: ["definitions"],
  "tencent-translate": ["definitions"],
};

function providerKey(provider: DictionaryProvider): InitializationProviderId {
  return provider.id.startsWith("ai:") ? "ai" : provider.id as InitializationProviderId;
}

function createProvider(id: InitializationProviderId, settings: AppSettings): DictionaryProvider | null {
  if (id === "merriam-webster") return settings.merriamWebsterEnabled ? new MerriamWebsterProvider(settings) : null;
  if (id === "dictionaryapi.dev") return settings.dictionaryApiEnabled ? new DictionaryApiProvider() : null;
  if (id === "ai") return settings.llmConfig.ai.enabled ? new AiLexicalProvider(settings) : null;
  if (id === "mymemory") return settings.myMemoryEnabled ? new MyMemoryProvider() : null;
  if (id === "tencent-translate") {
    if (!settings.tencentTranslateEnabled || !settings.tencentTranslateSecretId.trim() || !settings.tencentTranslateSecretKey.trim()) return null;
    return new TencentTranslateProvider({ secretId: settings.tencentTranslateSecretId.trim(), secretKey: settings.tencentTranslateSecretKey.trim(), projectId: settings.tencentTranslateProjectId });
  }
  if (id === "youdao") return settings.youdaoEnabled ? new YoudaoProvider() : null;
  if (id === "iciba") return settings.icibaEnabled ? new IcibaProvider() : null;
  return null;
}

function providersFor(settings: AppSettings, selected?: InitializationProviderId[]): DictionaryProvider[] {
  let order: InitializationProviderId[];
  if (selected?.length) {
    order = [...new Set(selected)];
  } else if (settings.translationProviderOrder?.length) {
    // Use the saved order. AI is intentionally not appended: default initialization
    // must be dictionary-backed, while AI runs as an explicit supplemental task.
    order = [...settings.translationProviderOrder];
  } else {
    order = ["youdao", "iciba", "merriam-webster", "dictionaryapi.dev", "mymemory"];
  }
  return order.map((id) => createProvider(id, settings)).filter((provider): provider is DictionaryProvider => Boolean(provider));
}

function supportsRequestedFields(provider: DictionaryProvider, requestedFields: InitializationField[], input?: LookupInput): boolean {
  if (!requestedFields.length) return true;
  const capabilities = PROVIDER_CAPABILITIES[providerKey(provider)];
  const hasOverlap = requestedFields.some((field) => capabilities.includes(field));
  if (!hasOverlap) return false;
  // SENTENCE 场景下有道/iciba 实际只产 definitions/summary/examples/phrases，勾了 synonyms/wordFamily 等无效字段时直接跳过该来源
  if (input?.entryType === "SENTENCE") {
    const key = providerKey(provider);
    if (key === "youdao" || key === "iciba") {
      const SENTENCE_FIELDS: InitializationField[] = ["definitions", "summary", "examples", "phrases"];
      if (!requestedFields.some((field) => (SENTENCE_FIELDS as string[]).includes(field))) return false;
    }
  }
  return true;
}

function fallbackQualityScore(content: DictionaryContent, input: LookupInput): number {
  const targetDefs = content.definitions.filter((item) => item.language === input.targetLanguage && item.text.trim());
  const hasTargetDef = targetDefs.length > 0 ? 1 : content.definitions.some((item) => item.text.trim()) ? 0.5 : 0;
  const hasEnoughExamples = content.examples.length >= 2 ? 1 : content.examples.length >= 1 ? 0.5 : 0;
  const hasPhonetics = content.pronunciations.some((item) => Boolean(item.phonetic?.trim())) ? 1 : 0;
  let score = hasTargetDef * 0.5 + hasEnoughExamples * 0.3 + hasPhonetics * 0.2;
  if (input.entryType === "SENTENCE") {
    const hasTranslation = Boolean(content.summary.translation?.trim());
    // 句子必须有译文才算高质量，否则即使 READY 也不截断
    if (!hasTranslation) score = Math.min(score, 0.6);
  }
  return score;
}

function requestedContentReady(
  content: DictionaryContent,
  requestedFields: InitializationField[],
  input: LookupInput,
): boolean {
  return requestedFieldStatusForLanguages(
    content,
    requestedFields,
    input.sourceLanguage,
    input.targetLanguage,
  ) === "READY";
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
}> {
  const requestedFields = normalizeRequestedFields(input.requestedFields);
  const providers = providersFor(settings, input.requestedProviders)
    .filter((provider) => provider.supports(input) && supportsRequestedFields(provider, requestedFields, input));

  let settled: SettledProvider[];
  if (input.providerStrategy === "PRIORITY_FALLBACK") {
    settled = [];
    let accumulated = mergeDictionaryContent();
    for (const provider of providers) {
      const result = await runProvider(provider, input, requestedFields);
      settled.push(result);
      if (result.content) accumulated = mergeDictionaryContent(accumulated, result.content);
      if (requestedContentReady(accumulated, requestedFields, input)) {
        if (fallbackQualityScore(accumulated, input) >= 0.8) break;
      }
    }
  } else {
    settled = await Promise.all(providers.map((provider) => runProvider(provider, input, requestedFields)));
  }

  let content = mergeDictionaryContent(...settled.map((item) => item.content));

  // 释义降级：主数据来源都没有返回释义时，依次尝试腾讯翻译和 AI
  const needsDefinitionFallback =
    contentStatus(content, input.entryType) === "FAILED" &&
    (!requestedFields.length || requestedFields.includes("definitions") || requestedFields.includes("summary"));
  const isYoudaoOnlySentence =
    input.requestedProviders?.length === 1 &&
    input.requestedProviders[0] === "youdao" &&
    input.entryType === "SENTENCE" &&
    (!requestedFields.length || requestedFields.includes("definitions") || requestedFields.includes("summary"));
  const allowFallback = !input.requestedProviders?.length || isYoudaoOnlySentence;
  // An explicit provider list is an intentional source boundary. Do not silently
  // add Tencent or AI when a user selected a specific dictionary, such as Youdao.
  // Exception: YOUDAO_ONLY + SENTENCE 允许受控回退到腾讯翻译，避免句子必败。
  if (needsDefinitionFallback && allowFallback) {
    const attempted = new Set(settled.map((item) => item.attempt.providerId.startsWith("ai:") ? "ai" : item.attempt.providerId));
    const fallbackIds: InitializationProviderId[] = isYoudaoOnlySentence ? ["tencent-translate"] : ["tencent-translate", "ai"];
    for (const fallbackId of fallbackIds) {
      if (attempted.has(fallbackId)) continue;
      const provider = createProvider(fallbackId, settings);
      if (!provider || !provider.supports(input)) continue;
      const result = await runProvider(provider, input, requestedFields);
      settled.push(result);
      if (result.content) content = mergeDictionaryContent(content, result.content);
      if (contentStatus(content, input.entryType) !== "FAILED") break;
    }
  }

  const aiResult = settled.find((item) => item.attempt.providerId.startsWith("ai:"));
  const aiSuccess = aiResult?.attempt.status === "SUCCESS";
  const nonAiSuccess = settled.some((item) => !item.attempt.providerId.startsWith("ai:") && item.attempt.status === "SUCCESS");
  const contentSource = aiSuccess && !nonAiSuccess ? "AI_ONLY" as const : aiSuccess ? "MIXED" as const : "DICTIONARY_ONLY" as const;
  return {
    content,
    attempts: settled.map((item) => item.attempt),
    hasTransientFailure: settled.some((item) => item.transient),
    contentSource,
  };
}
