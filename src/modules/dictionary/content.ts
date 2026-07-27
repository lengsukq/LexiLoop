import type {
  AffixItem,
  DictionaryContent,
  LearningContent,
  LexicalSummary,
  RelatedWordItem,
  RootItem,
  SentenceAnalysis,
} from "@/lib/types";

const EMPTY_SUMMARY: LexicalSummary = {
  shortDefinition: null,
  translation: null,
  cefrLevel: null,
  frequency: null,
};

const EMPTY_LEARNING: LearningContent = {
  pronunciationTip: null,
  mnemonic: null,
  commonMistakes: [],
};

const EMPTY_SENTENCE_ANALYSIS: SentenceAnalysis = {
  grammarNotes: [],
  keyExpressions: [],
  variations: [],
};

function parseJson<T>(value: unknown, fallback: T): T {
  if (value === null || value === undefined) return fallback;
  if (typeof value !== "string") return value as T;
  try { return JSON.parse(value) as T; } catch { return fallback; }
}

function cleanText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizeRelatedItems(value: unknown, relation: string, source = "legacy"): RelatedWordItem[] {
  const input = parseJson<unknown[]>(value, []);
  if (!Array.isArray(input)) return [];
  const result: RelatedWordItem[] = [];
  for (const item of input) {
    if (typeof item === "string") {
      const word = item.trim();
      if (word) result.push({ word, translation: null, partOfSpeech: null, relation, source });
      continue;
    }
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    const word = cleanText(record.word);
    if (!word) continue;
    result.push({
      word,
      translation: cleanText(record.translation) || null,
      partOfSpeech: cleanText(record.partOfSpeech) || null,
      relation: cleanText(record.relation) || relation,
      source: cleanText(record.source) || source,
      difference: cleanText(record.difference) || null,
    });
  }
  return result;
}

function normalizeRoots(value: unknown): RootItem[] {
  const input = parseJson<unknown[]>(value, []);
  if (!Array.isArray(input)) return [];
  return input.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>;
    const root = cleanText(record.root);
    const meaning = cleanText(record.meaning);
    if (!root || !meaning) return [];
    return [{ root, meaning, origin: cleanText(record.origin) || null, source: cleanText(record.source) || "legacy" }];
  });
}

function normalizeAffixes(value: unknown): AffixItem[] {
  const input = parseJson<unknown[]>(value, []);
  if (!Array.isArray(input)) return [];
  return input.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const record = item as Record<string, unknown>;
    const affix = cleanText(record.value);
    const meaning = cleanText(record.meaning);
    const type = record.type === "PREFIX" || record.type === "SUFFIX" ? record.type : null;
    if (!affix || !meaning || !type) return [];
    return [{ value: affix, meaning, type, source: cleanText(record.source) || "legacy" }];
  });
}

export function emptyDictionaryContent(): DictionaryContent {
  return {
    definitions: [], pronunciations: [], examples: [], phrases: [], forms: [],
    synonyms: [], antonyms: [], wordFamily: [], confusedWords: [], roots: [], affixes: [],
    summary: { ...EMPTY_SUMMARY }, learning: { ...EMPTY_LEARNING, commonMistakes: [] },
    sentenceAnalysis: { ...EMPTY_SENTENCE_ANALYSIS, grammarNotes: [], keyExpressions: [], variations: [] }, tags: [],
  };
}

export function normalizeDictionaryContent(content: Partial<DictionaryContent> | Record<string, unknown> | null | undefined): DictionaryContent {
  if (!content) return emptyDictionaryContent();
  const source = content as Record<string, unknown>;
  const summary = parseJson<Partial<LexicalSummary>>(source.summary, {});
  const learning = parseJson<Partial<LearningContent>>(source.learning, {});
  const sentenceAnalysis = parseJson<Partial<SentenceAnalysis>>(source.sentenceAnalysis, {});
  return {
    definitions: parseJson(source.definitions, []),
    pronunciations: parseJson(source.pronunciations, []),
    examples: parseJson(source.examples, []),
    phrases: parseJson(source.phrases, []),
    forms: parseJson(source.forms, []),
    synonyms: normalizeRelatedItems(source.synonyms, "SYNONYM"),
    antonyms: normalizeRelatedItems(source.antonyms, "ANTONYM"),
    wordFamily: normalizeRelatedItems(source.wordFamily, "WORD_FAMILY"),
    confusedWords: normalizeRelatedItems(source.confusedWords, "CONFUSED_WITH"),
    roots: normalizeRoots(source.roots),
    affixes: normalizeAffixes(source.affixes),
    summary: {
      shortDefinition: cleanText(summary.shortDefinition) || null,
      translation: cleanText(summary.translation) || null,
      cefrLevel: summary.cefrLevel ?? null,
      frequency: summary.frequency ?? null,
    },
    learning: {
      pronunciationTip: cleanText(learning.pronunciationTip) || null,
      mnemonic: cleanText(learning.mnemonic) || null,
      commonMistakes: Array.isArray(learning.commonMistakes) ? learning.commonMistakes.map(cleanText).filter(Boolean) : [],
    },
    sentenceAnalysis: {
      grammarNotes: Array.isArray(sentenceAnalysis.grammarNotes) ? sentenceAnalysis.grammarNotes.map(cleanText).filter(Boolean) : [],
      keyExpressions: Array.isArray(sentenceAnalysis.keyExpressions) ? sentenceAnalysis.keyExpressions.flatMap((item) => {
        if (!item || typeof item !== "object") return [];
        const record = item as Record<string, unknown>;
        const expression = cleanText(record.expression);
        const meaning = cleanText(record.meaning);
        return expression && meaning ? [{ expression, meaning, note: cleanText(record.note) || null }] : [];
      }) : [],
      variations: Array.isArray(sentenceAnalysis.variations) ? sentenceAnalysis.variations.flatMap((item) => {
        if (!item || typeof item !== "object") return [];
        const record = item as Record<string, unknown>;
        const sentence = cleanText(record.sentence);
        return sentence ? [{ sentence, translation: cleanText(record.translation) || null }] : [];
      }) : [],
    },
    tags: parseJson<string[]>(source.tags, []).map(cleanText).filter(Boolean),
  };
}

export function dictionaryContentFromRow(row: Record<string, unknown> | undefined): DictionaryContent {
  if (!row) return emptyDictionaryContent();
  return normalizeDictionaryContent({
    definitions: parseJson(row.definitions_json, []),
    pronunciations: parseJson(row.pronunciations_json, []),
    examples: parseJson(row.examples_json, []),
    phrases: parseJson(row.phrases_json, []),
    forms: parseJson(row.forms_json, []),
    synonyms: parseJson(row.synonyms_json, []),
    antonyms: parseJson(row.antonyms_json, []),
    wordFamily: parseJson(row.word_family_json, []),
    confusedWords: parseJson(row.confused_words_json, []),
    roots: parseJson(row.roots_json, []),
    affixes: parseJson(row.affixes_json, []),
    summary: parseJson(row.summary_json, EMPTY_SUMMARY),
    learning: parseJson(row.learning_json, EMPTY_LEARNING),
    sentenceAnalysis: parseJson(row.sentence_analysis_json, EMPTY_SENTENCE_ANALYSIS),
    tags: parseJson(row.tags_json, []),
  });
}

function mergeRelated(target: RelatedWordItem[], incoming: RelatedWordItem[]): void {
  const keys = new Set(target.map((item) => item.word.trim().toLocaleLowerCase()));
  for (const item of incoming) {
    const key = item.word.trim().toLocaleLowerCase();
    if (!key || keys.has(key)) continue;
    keys.add(key);
    target.push(item);
  }
}

export function mergeDictionaryContent(...contents: Array<Partial<DictionaryContent> | null | undefined>): DictionaryContent {
  const result = emptyDictionaryContent();
  const definitionKeys = new Set<string>();
  const pronunciationKeys = new Set<string>();
  const exampleKeys = new Set<string>();
  const phraseKeys = new Set<string>();
  const formKeys = new Set<string>();
  const rootKeys = new Set<string>();
  const affixKeys = new Set<string>();
  const tags = new Set<string>();

  for (const raw of contents) {
    const content = normalizeDictionaryContent(raw);
    for (const item of content.definitions) {
      const key = `${item.language}|${item.partOfSpeech ?? ""}|${item.text.trim().toLocaleLowerCase()}`;
      if (!definitionKeys.has(key)) { definitionKeys.add(key); result.definitions.push(item); }
    }
    for (const item of content.pronunciations) {
      const key = `${item.accent}|${item.phonetic ?? ""}|${item.audioUrl ?? ""}`;
      if (!pronunciationKeys.has(key)) { pronunciationKeys.add(key); result.pronunciations.push(item); }
    }
    for (const item of content.examples) {
      const key = item.sentence.trim().toLocaleLowerCase();
      if (!exampleKeys.has(key)) { exampleKeys.add(key); result.examples.push(item); }
    }
    for (const item of content.phrases) {
      const key = `${item.phrase.trim().toLocaleLowerCase()}|${item.translation ?? ""}`;
      if (!phraseKeys.has(key)) { phraseKeys.add(key); result.phrases.push(item); }
    }
    for (const item of content.forms) {
      const key = `${item.type}|${item.value.trim().toLocaleLowerCase()}`;
      if (!formKeys.has(key)) { formKeys.add(key); result.forms.push(item); }
    }
    mergeRelated(result.synonyms, content.synonyms);
    mergeRelated(result.antonyms, content.antonyms);
    mergeRelated(result.wordFamily, content.wordFamily);
    mergeRelated(result.confusedWords, content.confusedWords);
    for (const item of content.roots) {
      const key = `${item.root.toLocaleLowerCase()}|${item.meaning.toLocaleLowerCase()}`;
      if (!rootKeys.has(key)) { rootKeys.add(key); result.roots.push(item); }
    }
    for (const item of content.affixes) {
      const key = `${item.type}|${item.value.toLocaleLowerCase()}`;
      if (!affixKeys.has(key)) { affixKeys.add(key); result.affixes.push(item); }
    }
    result.summary = {
      shortDefinition: result.summary.shortDefinition ?? content.summary.shortDefinition,
      translation: result.summary.translation ?? content.summary.translation,
      cefrLevel: result.summary.cefrLevel ?? content.summary.cefrLevel,
      frequency: result.summary.frequency ?? content.summary.frequency,
    };
    result.learning = {
      pronunciationTip: result.learning.pronunciationTip ?? content.learning.pronunciationTip,
      mnemonic: result.learning.mnemonic ?? content.learning.mnemonic,
      commonMistakes: [...new Set([...result.learning.commonMistakes, ...content.learning.commonMistakes])],
    };
    result.sentenceAnalysis = {
      grammarNotes: [...new Set([...result.sentenceAnalysis.grammarNotes, ...content.sentenceAnalysis.grammarNotes])],
      keyExpressions: [...result.sentenceAnalysis.keyExpressions, ...content.sentenceAnalysis.keyExpressions.filter((incoming) => !result.sentenceAnalysis.keyExpressions.some((current) => current.expression.toLocaleLowerCase() === incoming.expression.toLocaleLowerCase()))],
      variations: [...result.sentenceAnalysis.variations, ...content.sentenceAnalysis.variations.filter((incoming) => !result.sentenceAnalysis.variations.some((current) => current.sentence.toLocaleLowerCase() === incoming.sentence.toLocaleLowerCase()))],
    };
    for (const value of content.tags) tags.add(value);
  }
  result.tags = [...tags];
  return result;
}

export function contentStatus(content: DictionaryContent): "READY" | "PARTIAL" | "FAILED" {
  if (content.definitions.length === 0) return "FAILED";
  return content.examples.length > 0 ? "READY" : "PARTIAL";
}
