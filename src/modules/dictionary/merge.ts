import type { DictionaryContent, EntryType, RelatedWordItem } from "@/lib/types";
import { emptyDictionaryContent, normalizeDictionaryContent } from "./content";

function mergeRelated(target: RelatedWordItem[], incoming: RelatedWordItem[]): void {
  const keys = new Set(target.map((item) => item.word.trim().toLocaleLowerCase()));
  for (const item of incoming) {
    const key = item.word.trim().toLocaleLowerCase();
    if (!key || keys.has(key)) continue;
    keys.add(key); target.push(item);
  }
}

function textSimilarity(a: string, b: string): number {
  const clean = (value: string) => value.replace(/[\s\p{P}]/gu, "");
  const left = new Set(clean(a)); const right = new Set(clean(b));
  if (left.size === 0 && right.size === 0) return 1;
  if (left.size === 0 || right.size === 0) return 0;
  let intersection = 0;
  for (const character of left) if (right.has(character)) intersection++;
  return intersection / (left.size + right.size - intersection);
}

function deduplicateSimilarDefinitions(definitions: DictionaryContent["definitions"]): DictionaryContent["definitions"] {
  const groups = new Map<string, DictionaryContent["definitions"]>();
  for (const item of definitions) {
    const key = `${item.language}|${item.partOfSpeech ?? ""}`;
    groups.set(key, [...(groups.get(key) ?? []), item]);
  }
  const result: DictionaryContent["definitions"] = [];
  for (const group of groups.values()) {
    const kept: DictionaryContent["definitions"] = [];
    for (const item of group) {
      if (item.isUserEdited) { kept.push(item); continue; }
      const duplicate = kept.find((existing) => !existing.isUserEdited && textSimilarity(existing.text, item.text) >= 0.72);
      if (!duplicate) kept.push(item);
      else if (item.text.length > duplicate.text.length) kept[kept.indexOf(duplicate)] = item;
    }
    result.push(...kept);
  }
  return result;
}

export function mergeDictionaryContent(...contents: Array<Partial<DictionaryContent> | null | undefined>): DictionaryContent {
  const result = emptyDictionaryContent();
  const definitions = new Set<string>();
  const pronunciations = new Set<string>();
  const examples = new Set<string>();
  const phrases = new Set<string>();
  const forms = new Set<string>();
  const roots = new Set<string>();
  const affixes = new Set<string>();
  const tags = new Set<string>();
  for (const raw of contents) {
    const content = normalizeDictionaryContent(raw);
    for (const item of content.definitions) { const key = `${item.language}|${item.partOfSpeech ?? ""}|${item.text.trim().toLocaleLowerCase()}`; if (!definitions.has(key)) { definitions.add(key); result.definitions.push(item); } }
    for (const item of content.pronunciations) { const key = `${item.accent}|${item.phonetic ?? ""}|${item.audioUrl ?? ""}`; if (!pronunciations.has(key)) { pronunciations.add(key); result.pronunciations.push(item); } }
    for (const item of content.examples) { const key = item.sentence.trim().toLocaleLowerCase(); if (!examples.has(key)) { examples.add(key); result.examples.push(item); } }
    for (const item of content.phrases) { const key = `${item.phrase.trim().toLocaleLowerCase()}|${item.translation ?? ""}`; if (!phrases.has(key)) { phrases.add(key); result.phrases.push(item); } }
    for (const item of content.forms) { const key = `${item.type}|${item.value.trim().toLocaleLowerCase()}`; if (!forms.has(key)) { forms.add(key); result.forms.push(item); } }
    mergeRelated(result.synonyms, content.synonyms); mergeRelated(result.antonyms, content.antonyms); mergeRelated(result.wordFamily, content.wordFamily); mergeRelated(result.confusedWords, content.confusedWords);
    for (const item of content.roots) { const key = `${item.root.toLocaleLowerCase()}|${item.meaning.toLocaleLowerCase()}`; if (!roots.has(key)) { roots.add(key); result.roots.push(item); } }
    for (const item of content.affixes) { const key = `${item.type}|${item.value.toLocaleLowerCase()}`; if (!affixes.has(key)) { affixes.add(key); result.affixes.push(item); } }
    result.summary = { shortDefinition: result.summary.shortDefinition ?? content.summary.shortDefinition, translation: result.summary.translation ?? content.summary.translation, cefrLevel: result.summary.cefrLevel ?? content.summary.cefrLevel, frequency: result.summary.frequency ?? content.summary.frequency };
    result.learning = { pronunciationTip: result.learning.pronunciationTip ?? content.learning.pronunciationTip, mnemonic: result.learning.mnemonic ?? content.learning.mnemonic, commonMistakes: [...new Set([...result.learning.commonMistakes, ...content.learning.commonMistakes])] };
    result.sentenceAnalysis = {
      grammarPattern: result.sentenceAnalysis.grammarPattern ?? content.sentenceAnalysis.grammarPattern,
      grammarExplanation: result.sentenceAnalysis.grammarExplanation ?? content.sentenceAnalysis.grammarExplanation,
      grammarNotes: [...new Set([...result.sentenceAnalysis.grammarNotes, ...content.sentenceAnalysis.grammarNotes])],
      keyExpressions: [...result.sentenceAnalysis.keyExpressions, ...content.sentenceAnalysis.keyExpressions.filter((item) => !result.sentenceAnalysis.keyExpressions.some((current) => current.expression.toLocaleLowerCase() === item.expression.toLocaleLowerCase()))],
      similarExamples: [...result.sentenceAnalysis.similarExamples, ...content.sentenceAnalysis.similarExamples.filter((item) => !result.sentenceAnalysis.similarExamples.some((current) => current.sentence.toLocaleLowerCase() === item.sentence.toLocaleLowerCase()))],
      variations: [...result.sentenceAnalysis.variations, ...content.sentenceAnalysis.variations.filter((item) => !result.sentenceAnalysis.variations.some((current) => current.sentence.toLocaleLowerCase() === item.sentence.toLocaleLowerCase()))],
    };
    for (const value of content.tags) tags.add(value);
  }
  result.tags = [...tags]; result.definitions = deduplicateSimilarDefinitions(result.definitions); return result;
}

export function contentStatus(content: DictionaryContent, entryType: EntryType = "WORD"): "READY" | "PARTIAL" | "FAILED" {
  if (entryType === "SENTENCE") {
    const hasMeaning = content.definitions.some((item) => item.text.trim()) || Boolean(content.summary.translation?.trim()) || Boolean(content.summary.shortDefinition?.trim());
    if (!hasMeaning) return "FAILED";
    const hasAnalysis = Boolean(content.sentenceAnalysis.grammarPattern || content.sentenceAnalysis.grammarExplanation) || content.sentenceAnalysis.grammarNotes.length > 0 || content.sentenceAnalysis.keyExpressions.length > 0 || content.sentenceAnalysis.similarExamples.length > 0 || content.sentenceAnalysis.variations.length > 0;
    return hasAnalysis ? "READY" : "PARTIAL";
  }
  if (content.definitions.length === 0) return "FAILED";
  return content.examples.length > 0 ? "READY" : "PARTIAL";
}
