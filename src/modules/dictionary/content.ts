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

export function emptyDictionaryContent(): DictionaryContent {
  return { definitions: [], pronunciations: [], examples: [], phrases: [], forms: [], synonyms: [], antonyms: [], wordFamily: [], confusedWords: [], roots: [], affixes: [], summary: { ...EMPTY_SUMMARY }, learning: { ...EMPTY_LEARNING, commonMistakes: [] }, sentenceAnalysis: { ...EMPTY_SENTENCE_ANALYSIS, grammarNotes: [], keyExpressions: [], similarExamples: [], variations: [] }, tags: [] };
}

export function normalizeDictionaryContent(content: Partial<DictionaryContent> | Record<string, unknown> | null | undefined): DictionaryContent {
  if (!content) return emptyDictionaryContent();
  const source = content as Record<string, unknown>; const summary = parseJson<Partial<LexicalSummary>>(source.summary, {}); const learning = parseJson<Partial<LearningContent>>(source.learning, {}); const sentence = parseJson<Partial<SentenceAnalysis>>(source.sentenceAnalysis, {});
  return {
    definitions: parseJson(source.definitions, []), pronunciations: normalizePronunciations(source.pronunciations), examples: parseJson(source.examples, []), phrases: parseJson(source.phrases, []), forms: parseJson(source.forms, []),
    synonyms: normalizeRelatedItems(source.synonyms, "SYNONYM"), antonyms: normalizeRelatedItems(source.antonyms, "ANTONYM"), wordFamily: normalizeRelatedItems(source.wordFamily, "WORD_FAMILY"), confusedWords: normalizeRelatedItems(source.confusedWords, "CONFUSED_WITH"), roots: normalizeRoots(source.roots), affixes: normalizeAffixes(source.affixes),
    summary: { shortDefinition: cleanText(summary.shortDefinition) || null, translation: cleanText(summary.translation) || null, cefrLevel: summary.cefrLevel ?? null, frequency: summary.frequency ?? null },
    learning: { pronunciationTip: cleanText(learning.pronunciationTip) || null, mnemonic: cleanText(learning.mnemonic) || null, commonMistakes: Array.isArray(learning.commonMistakes) ? learning.commonMistakes.map(cleanText).filter(Boolean) : [] },
    sentenceAnalysis: { grammarPattern: cleanText(sentence.grammarPattern) || null, grammarExplanation: cleanText(sentence.grammarExplanation) || null, grammarNotes: Array.isArray(sentence.grammarNotes) ? sentence.grammarNotes.map(cleanText).filter(Boolean) : [], keyExpressions: Array.isArray(sentence.keyExpressions) ? sentence.keyExpressions.flatMap((item) => { if (!item || typeof item !== "object") return []; const r = item as unknown as Record<string, unknown>; const expression = cleanText(r.expression); const meaning = cleanText(r.meaning); return expression && meaning ? [{ expression, meaning, note: cleanText(r.note) || null }] : []; }) : [], similarExamples: Array.isArray(sentence.similarExamples) ? sentence.similarExamples.flatMap((item) => { if (!item || typeof item !== "object") return []; const r = item as unknown as Record<string, unknown>; const value = cleanText(r.sentence); const translation = cleanText(r.translation); return value && translation ? [{ sentence: value, translation, focus: cleanText(r.focus) || null }] : []; }) : [], variations: Array.isArray(sentence.variations) ? sentence.variations.flatMap((item) => { if (!item || typeof item !== "object") return []; const r = item as unknown as Record<string, unknown>; const value = cleanText(r.sentence); return value ? [{ sentence: value, translation: cleanText(r.translation) || null }] : []; }) : [] },
    tags: parseJson<string[]>(source.tags, []).map(cleanText).filter(Boolean),
  };
}

export function dictionaryContentFromRow(row: Record<string, unknown> | undefined): DictionaryContent {
  if (!row) return emptyDictionaryContent();
  return normalizeDictionaryContent(Object.fromEntries(Object.entries({ definitions: row.definitions_json, pronunciations: row.pronunciations_json, examples: row.examples_json, phrases: row.phrases_json, forms: row.forms_json, synonyms: row.synonyms_json, antonyms: row.antonyms_json, wordFamily: row.word_family_json, confusedWords: row.confused_words_json, roots: row.roots_json, affixes: row.affixes_json, summary: row.summary_json, learning: row.learning_json, sentenceAnalysis: row.sentence_analysis_json, tags: row.tags_json }).map(([key, value]) => [key, parseJson(value, [])])));
}

export { contentStatus, mergeDictionaryContent } from "./merge";
