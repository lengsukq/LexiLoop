import { parseJson } from "@/lib/json";
import type { AffixItem, DictionaryContent, LearningContent, LexicalSummary, PronunciationItem, RelatedWordItem, RootItem, SentenceAnalysis } from "@/lib/types";

const EMPTY_SUMMARY: LexicalSummary = { shortDefinition: null, translation: null, cefrLevel: null, frequency: null };
const EMPTY_LEARNING: LearningContent = { pronunciationTip: null, mnemonic: null, commonMistakes: [] };
const EMPTY_SENTENCE_ANALYSIS: SentenceAnalysis = { grammarPattern: null, grammarExplanation: null, grammarNotes: [], keyExpressions: [], similarExamples: [], variations: [] };
const cleanText = (value: unknown): string => typeof value === "string" ? value.trim() : "";

function normalizeRelatedItems(value: unknown, relation: string, source = "legacy"): RelatedWordItem[] {
  const input = parseJson<unknown[]>(value, []); if (!Array.isArray(input)) return [];
  return input.flatMap((item): RelatedWordItem[] => {
    if (typeof item === "string") { const word = item.trim(); return word ? [{ word, translation: null, partOfSpeech: null, relation, source }] : []; }
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>; const word = cleanText(record.word); if (!word) return [];
    return [{ word, translation: cleanText(record.translation) || null, partOfSpeech: cleanText(record.partOfSpeech) || null, relation: cleanText(record.relation) || relation, source: cleanText(record.source) || source, difference: cleanText(record.difference) || null }];
  });
}
function normalizeRoots(value: unknown): RootItem[] {
  const input = parseJson<unknown[]>(value, []); if (!Array.isArray(input)) return [];
  return input.flatMap((item) => { if (!item || typeof item !== "object") return []; const record = item as Record<string, unknown>; const root = cleanText(record.root); const meaning = cleanText(record.meaning); return root && meaning ? [{ root, meaning, origin: cleanText(record.origin) || null, source: cleanText(record.source) || "legacy" }] : []; });
}
function normalizeAffixes(value: unknown): AffixItem[] {
  const input = parseJson<unknown[]>(value, []); if (!Array.isArray(input)) return [];
  return input.flatMap((item) => { if (!item || typeof item !== "object") return []; const record = item as Record<string, unknown>; const value = cleanText(record.value); const meaning = cleanText(record.meaning); const type = record.type === "PREFIX" || record.type === "SUFFIX" ? record.type : null; return value && meaning && type ? [{ value, meaning, type, source: cleanText(record.source) || "legacy" }] : []; });
}
function normalizePronunciations(value: unknown): PronunciationItem[] {
  const input = parseJson<unknown[]>(value, []); if (!Array.isArray(input)) return [];
  return input.flatMap((item): PronunciationItem[] => {
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>;
    const phonetic = cleanText(record.phonetic);
    if (!phonetic) return [];
    return [{
      accent: record.accent === "UK" ? "UK" : "US",
      phonetic,
      audioUrl: cleanText(record.audioUrl) || null,
      source: cleanText(record.source) || "legacy",
      isSynthetic: Boolean(record.isSynthetic),
    }];
  });
}

type KeyExpression = { expression: string; meaning: string; note: string | null };
type SimilarExample = { sentence: string; translation: string; focus: string | null };
type SentenceVariation = { sentence: string; translation: string | null };

function normalizeKeyExpressions(value: unknown): KeyExpression[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): KeyExpression[] => {
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>;
    const expression = cleanText(record.expression);
    const meaning = cleanText(record.meaning);
    return expression && meaning ? [{ expression, meaning, note: cleanText(record.note) || null }] : [];
  });
}

function normalizeSimilarExamples(value: unknown): SimilarExample[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): SimilarExample[] => {
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>;
    const sentence = cleanText(record.sentence);
    const translation = cleanText(record.translation);
    return sentence && translation ? [{ sentence, translation, focus: cleanText(record.focus) || null }] : [];
  });
}

function normalizeSentenceVariations(value: unknown): SentenceVariation[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item): SentenceVariation[] => {
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>;
    const sentence = cleanText(record.sentence);
    return sentence ? [{ sentence, translation: cleanText(record.translation) || null }] : [];
  });
}

function normalizeStringList(value: unknown): string[] {
  return Array.isArray(value) ? value.map(cleanText).filter(Boolean) : [];
}

function normalizeSentenceAnalysis(value: unknown): SentenceAnalysis {
  const sentence = parseJson<Partial<SentenceAnalysis>>(value, {});
  return {
    grammarPattern: cleanText(sentence.grammarPattern) || null,
    grammarExplanation: cleanText(sentence.grammarExplanation) || null,
    grammarNotes: normalizeStringList(sentence.grammarNotes),
    keyExpressions: normalizeKeyExpressions(sentence.keyExpressions),
    similarExamples: normalizeSimilarExamples(sentence.similarExamples),
    variations: normalizeSentenceVariations(sentence.variations),
  };
}

export function emptyDictionaryContent(): DictionaryContent {
  return { definitions: [], pronunciations: [], examples: [], phrases: [], forms: [], synonyms: [], antonyms: [], wordFamily: [], confusedWords: [], roots: [], affixes: [], summary: { ...EMPTY_SUMMARY }, learning: { ...EMPTY_LEARNING, commonMistakes: [] }, sentenceAnalysis: { ...EMPTY_SENTENCE_ANALYSIS, grammarNotes: [], keyExpressions: [], similarExamples: [], variations: [] }, tags: [] };
}

export function normalizeDictionaryContent(content: Partial<DictionaryContent> | Record<string, unknown> | null | undefined): DictionaryContent {
  if (!content) return emptyDictionaryContent();
  const source = content as Record<string, unknown>;
  const summary = parseJson<Partial<LexicalSummary>>(source.summary, {});
  const learning = parseJson<Partial<LearningContent>>(source.learning, {});
  return {
    definitions: parseJson(source.definitions, []),
    pronunciations: normalizePronunciations(source.pronunciations),
    examples: parseJson(source.examples, []),
    phrases: parseJson(source.phrases, []),
    forms: parseJson(source.forms, []),
    synonyms: normalizeRelatedItems(source.synonyms, "SYNONYM"),
    antonyms: normalizeRelatedItems(source.antonyms, "ANTONYM"),
    wordFamily: normalizeRelatedItems(source.wordFamily, "WORD_FAMILY"),
    confusedWords: normalizeRelatedItems(source.confusedWords, "CONFUSED_WITH"),
    roots: normalizeRoots(source.roots),
    affixes: normalizeAffixes(source.affixes),
    summary: { shortDefinition: cleanText(summary.shortDefinition) || null, translation: cleanText(summary.translation) || null, cefrLevel: summary.cefrLevel ?? null, frequency: summary.frequency ?? null },
    learning: { pronunciationTip: cleanText(learning.pronunciationTip) || null, mnemonic: cleanText(learning.mnemonic) || null, commonMistakes: normalizeStringList(learning.commonMistakes) },
    sentenceAnalysis: normalizeSentenceAnalysis(source.sentenceAnalysis),
    tags: normalizeStringList(source.tags),
  };
}

export function dictionaryContentFromRow(row: Record<string, unknown> | undefined): DictionaryContent {
  if (!row) return emptyDictionaryContent();
  return normalizeDictionaryContent(Object.fromEntries(Object.entries({ definitions: row.definitions_json, pronunciations: row.pronunciations_json, examples: row.examples_json, phrases: row.phrases_json, forms: row.forms_json, synonyms: row.synonyms_json, antonyms: row.antonyms_json, wordFamily: row.word_family_json, confusedWords: row.confused_words_json, roots: row.roots_json, affixes: row.affixes_json, summary: row.summary_json, learning: row.learning_json, sentenceAnalysis: row.sentence_analysis_json, tags: row.tags_json }).map(([key, value]) => [key, parseJson(value, [])])));
}

export { contentStatus, mergeDictionaryContent } from "./merge";
