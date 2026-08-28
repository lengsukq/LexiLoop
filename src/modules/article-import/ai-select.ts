import { callLlmWithFallback, resolveLlmProviders } from "@/modules/llm/client";
import { getSettings } from "@/modules/settings/service";
import type { VocabularyLevel } from "@/lib/types";
import { buildArticleSelectionPrompt, parseJsonLoose } from "./prompt";
import { normalizeLegacyResponse } from "./schema";

export interface AiSelectInput {
  articleText: string;
  candidates: Array<{ term: string; normalizedTerm: string; occurrences: number; sourceSentence?: string | null }>;
  knownSample: string[];
  totalKnown: number;
  vocabularyLevel: VocabularyLevel;
}

export interface AiSelectResult {
  applied: boolean;
  words: Array<{ term: string; reason: string; difficulty: number; cefrLevel: string | null; frequency: string | null }>;
  phrases: Array<{ term: string; reason: string; difficulty: number; cefrLevel: string | null; literalTranslation: string; freeTranslation: string; keyVocab: Array<{ term: string; pos: string | null; meaning: string }>; grammarPattern: string | null; grammarNotes: string[]; nuance: string | null }>;
  sentences: Array<{ sentence: string; literalTranslation: string; freeTranslation: string; keyVocab: Array<{ term: string; pos: string | null; meaning: string }>; grammarPattern: string | null; grammarNotes: string[]; nuance: string | null }>;
  // legacy alias
  selected: Array<{ term: string; reason: string; difficulty: number; cefrLevel: string | null; frequency: string | null }>;
  error?: string;
}

export async function aiSelectTerms(input: AiSelectInput): Promise<AiSelectResult> {
  const empty: AiSelectResult = { applied: false, words: [], phrases: [], sentences: [], selected: [], error: undefined };
  const settings = await getSettings();
  const { primary, fallback } = resolveLlmProviders(settings);
  if (!primary) {
    const purpose = settings.llmConfig.ai;
    if (!purpose?.enabled) return { ...empty, error: "AI 未启用，请到设置页开启 AI。" };
    return { ...empty, error: "AI 服务配置不完整，请到设置页补全。" };
  }
  const purpose = settings.llmConfig.ai;

  const { systemPrompt, userPrompt } = buildArticleSelectionPrompt({
    articleText: input.articleText,
    candidates: input.candidates,
    knownSample: input.knownSample,
    totalKnown: input.totalKnown,
    vocabularyLevel: input.vocabularyLevel,
  });

  let raw = "";
  try {
    raw = await callLlmWithFallback(primary, fallback, userPrompt, {
      systemPrompt,
      maxOutputTokens: Math.max(purpose.maxOutputTokens ?? 3000, 4500),
      temperature: purpose.temperature ?? 0.2,
      thinkingEnabled: purpose.thinkingEnabled ?? false,
      thinkingBudgetTokens: purpose.thinkingBudgetTokens,
      reasoningEffort: purpose.reasoningEffort,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "AI 请求失败";
    return { ...empty, error: message };
  }

  const parsed = parseJsonLoose(raw);
  if (!parsed) return { ...empty, error: "AI 返回内容不是有效 JSON，已回退为本地筛选。" };

  const normalized = normalizeLegacyResponse(parsed);
  if (!normalized) return { ...empty, error: "AI 返回格式不符合预期，已回退为本地筛选。" };

  const words = (normalized.words ?? []).map((item) => ({
    term: item.term,
    reason: item.reason,
    difficulty: item.difficulty,
    cefrLevel: item.cefrLevel ?? null,
    frequency: item.frequency ?? null,
  }));
  const phrases = (normalized.phrases ?? []).map((item) => ({
    term: item.term,
    reason: item.reason,
    difficulty: item.difficulty,
    cefrLevel: (item.cefrLevel ?? null) as string | null,
    literalTranslation: item.literalTranslation,
    freeTranslation: item.freeTranslation,
    keyVocab: (item.keyVocab ?? []).map((k) => ({ term: k.term, pos: k.pos ?? null, meaning: k.meaning })),
    grammarPattern: (item.grammar?.pattern ?? null) as string | null,
    grammarNotes: (item.grammar?.notes ?? []) as string[],
    nuance: (item.nuance ?? null) as string | null,
  }));
  const sentences = (normalized.sentences ?? []).map((item) => ({
    sentence: item.sentence,
    literalTranslation: item.literalTranslation,
    freeTranslation: item.freeTranslation,
    keyVocab: (item.keyVocab ?? []).map((k) => ({ term: k.term, pos: k.pos ?? null, meaning: k.meaning })),
    grammarPattern: (item.grammar?.pattern ?? null) as string | null,
    grammarNotes: (item.grammar?.notes ?? []) as string[],
    nuance: (item.nuance ?? null) as string | null,
  }));

  return { applied: true, words, phrases, sentences, selected: words };
}
