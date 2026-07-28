import type { AppSettings, DictionaryContent, LookupInput, ProviderAttempt } from "@/lib/types";
import type { DictionaryProvider } from "./provider";
import { DictionaryApiProvider } from "./providers/dictionary-api";
import { EcdictProvider } from "./providers/ecdict";
import { MyMemoryProvider } from "./providers/mymemory";
import { AiLexicalProvider } from "./providers/ai-lexical";
import { MerriamWebsterProvider } from "./providers/merriam-webster";
import { mergeDictionaryContent } from "./content";

function providersFor(settings: AppSettings): DictionaryProvider[] {
  const providers: DictionaryProvider[] = [];
  const aiProvider = new AiLexicalProvider(settings);
  if (settings.merriamWebsterEnabled) providers.push(new MerriamWebsterProvider(settings));
  if (settings.llmConfig.purposes.IMPORT_ENRICHMENT.enabled) {
    providers.push(aiProvider);
    // AI 负责核心学习内容；传统词典只补充音标、真人音频或离线词形。
    if (settings.dictionaryApiEnabled) providers.push(new DictionaryApiProvider());
    if (settings.ecdictEnabled) providers.push(new EcdictProvider());
    return providers;
  }
  if (settings.dictionaryApiEnabled) providers.push(new DictionaryApiProvider());
  if (settings.ecdictEnabled) providers.push(new EcdictProvider());
  if (settings.myMemoryEnabled) providers.push(new MyMemoryProvider());
  return providers;
}

export async function lookupDictionary(input: LookupInput, settings: AppSettings): Promise<{
  content: DictionaryContent;
  attempts: ProviderAttempt[];
  hasTransientFailure: boolean;
  contentSource: "AI_ONLY" | "MIXED" | "DICTIONARY_ONLY";
  requiredProviderFailure: null | {
    transient: boolean;
    errorCode: string;
    errorMessage: string;
  };
}> {
  const providers = providersFor(settings).filter((provider) => provider.supports(input));
  const settled = await Promise.all(providers.map(async (provider) => {
    const started = Date.now();
    try {
      const result = await provider.lookup(input);
      const fields = result.content ? Object.entries(result.content).filter(([, value]) => Array.isArray(value) && value.length > 0).map(([key]) => key) : [];
      const attempt: ProviderAttempt = {
        providerId: provider.id,
        status: result.content ? "SUCCESS" : result.errorCode === "NOT_FOUND" || result.errorCode === "EMPTY_RESULT" ? "EMPTY" : "FAILED",
        durationMs: Date.now() - started,
        fieldsReturned: fields,
        errorCode: result.errorCode,
        errorMessage: result.errorMessage,
        metadata: result.metadata,
      };
      return { content: result.content, attempt, transient: Boolean(result.transient) };
    } catch (error) {
      return {
        content: null,
        attempt: { providerId: provider.id, status: "FAILED" as const, durationMs: Date.now() - started, fieldsReturned: [], errorCode: "EXCEPTION", errorMessage: String(error) },
        transient: true,
      };
    }
  }));
  const aiRequired = settings.llmConfig.purposes.IMPORT_ENRICHMENT.enabled;
  const aiResult = settled.find((item) => item.attempt.providerId.startsWith("ai:"));
  const requiredProviderFailure = aiRequired && aiResult?.attempt.status !== "SUCCESS"
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
    content: mergeDictionaryContent(...settled.map((item) => item.content)),
    attempts: settled.map((item) => item.attempt),
    hasTransientFailure: settled.some((item) => item.transient),
    contentSource,
    requiredProviderFailure,
  };
}
