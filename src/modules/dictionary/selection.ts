import type { DictionaryContent, InitializationField, InitializationMode, PronunciationItem } from "@/lib/types";
import { INITIALIZATION_FIELDS } from "@/lib/types";
import { emptyDictionaryContent, mergeDictionaryContent, normalizeDictionaryContent } from "./content";

type SimpleArrayField =
  | "definitions" | "examples" | "phrases" | "forms" | "synonyms" | "antonyms"
  | "wordFamily" | "confusedWords" | "roots" | "affixes" | "tags";

export function normalizeRequestedFields(fields?: readonly string[] | null): InitializationField[] {
  if (!fields?.length) return [];
  const allowed = new Set<string>(INITIALIZATION_FIELDS);
  return [...new Set(fields.filter((field): field is InitializationField => allowed.has(field)))];
}

export function hasInitializationField(content: DictionaryContent, field: InitializationField): boolean {
  switch (field) {
    case "pronunciations.phonetic": return content.pronunciations.some((item) => Boolean(item.phonetic?.trim()));
    case "pronunciations.audio": return content.pronunciations.some((item) => Boolean(item.audioUrl?.trim()));
    case "summary": return Boolean(content.summary.shortDefinition || content.summary.translation || content.summary.cefrLevel || content.summary.frequency);
    case "learning": return Boolean(content.learning.pronunciationTip || content.learning.mnemonic || content.learning.commonMistakes.length);
    case "sentenceAnalysis": return Boolean(content.sentenceAnalysis.grammarNotes.length || content.sentenceAnalysis.keyExpressions.length || content.sentenceAnalysis.variations.length);
    default: return content[field as SimpleArrayField].length > 0;
  }
}

export function requestedFieldStatus(content: DictionaryContent, fields: readonly InitializationField[]): "READY" | "PARTIAL" | "FAILED" {
  if (!fields.length) return content.definitions.length ? (content.examples.length ? "READY" : "PARTIAL") : "FAILED";
  const present = fields.filter((field) => hasInitializationField(content, field)).length;
  if (present === fields.length) return "READY";
  return present > 0 ? "PARTIAL" : "FAILED";
}

export function requestedFieldStatusForLanguages(
  content: DictionaryContent,
  fields: readonly InitializationField[],
  sourceLanguage: string,
  targetLanguage: string,
): "READY" | "PARTIAL" | "FAILED" {
  const status = requestedFieldStatus(content, fields);
  const definitionsRequired = !fields.length || fields.includes("definitions");
  if (!definitionsRequired || sourceLanguage === targetLanguage) return status;

  const hasTargetDefinition = content.definitions.some((definition) =>
    definition.language === targetLanguage && definition.text.trim().length > 0,
  );
  if (hasTargetDefinition) return status;
  return content.definitions.some((definition) => definition.text.trim().length > 0)
    ? "PARTIAL"
    : status;
}

export function fieldsReturned(content: DictionaryContent, requestedFields: readonly InitializationField[]): InitializationField[] {
  const candidates = requestedFields.length ? requestedFields : INITIALIZATION_FIELDS;
  return candidates.filter((field) => hasInitializationField(content, field));
}

export function projectDictionaryContent(raw: Partial<DictionaryContent> | null | undefined, requestedFields: readonly InitializationField[]): DictionaryContent {
  const content = normalizeDictionaryContent(raw);
  if (!requestedFields.length) return content;
  const result = emptyDictionaryContent();
  for (const field of requestedFields) {
    if (field === "pronunciations.phonetic" || field === "pronunciations.audio") {
      result.pronunciations = content.pronunciations;
    } else if (field === "summary") result.summary = content.summary;
    else if (field === "learning") result.learning = content.learning;
    else if (field === "sentenceAnalysis") result.sentenceAnalysis = content.sentenceAnalysis;
    else result[field as SimpleArrayField] = content[field as SimpleArrayField] as never;
  }
  return result;
}

function clonePronunciations(items: PronunciationItem[]): PronunciationItem[] {
  return items.map((item) => ({ ...item }));
}

function mergePhonetic(existing: PronunciationItem[], incoming: PronunciationItem[], force: boolean): PronunciationItem[] {
  if (!incoming.some((item) => item.phonetic?.trim())) return clonePronunciations(existing);
  if (!force && existing.some((item) => item.phonetic?.trim())) return clonePronunciations(existing);
  const result = clonePronunciations(existing);
  if (force) for (const item of result) item.phonetic = null;
  for (const source of incoming.filter((item) => item.phonetic?.trim())) {
    const target = result.find((item) => item.accent === source.accent && !item.phonetic)
      ?? result.find((item) => item.accent === source.accent);
    if (target) {
      target.phonetic = source.phonetic;
      if (!target.audioUrl) target.source = source.source;
    } else {
      result.push({ ...source, audioUrl: null });
    }
  }
  return result.filter((item) => item.phonetic || item.audioUrl);
}

function mergeAudio(existing: PronunciationItem[], incoming: PronunciationItem[], force: boolean): PronunciationItem[] {
  if (!incoming.some((item) => item.audioUrl?.trim())) return clonePronunciations(existing);
  if (!force && existing.some((item) => item.audioUrl?.trim())) return clonePronunciations(existing);
  const result = clonePronunciations(existing);
  if (force) for (const item of result) item.audioUrl = null;
  for (const source of incoming.filter((item) => item.audioUrl?.trim())) {
    if (result.some((item) => item.audioUrl === source.audioUrl)) continue;
    const target = result.find((item) => item.accent === source.accent && !item.audioUrl);
    if (target) {
      target.audioUrl = source.audioUrl;
      if (!target.phonetic && source.phonetic) target.phonetic = source.phonetic;
      target.source = source.source;
      target.isSynthetic = source.isSynthetic;
    } else {
      result.push({ ...source });
    }
  }
  return result.filter((item) => item.phonetic || item.audioUrl);
}

export function mergeRequestedFields(
  existingRaw: DictionaryContent,
  incomingRaw: Partial<DictionaryContent> | null | undefined,
  requestedFields: readonly InitializationField[],
  mode: InitializationMode,
): DictionaryContent {
  const existing = normalizeDictionaryContent(existingRaw);
  const incoming = normalizeDictionaryContent(incomingRaw);
  if (!requestedFields.length) {
    return mode === "FORCE_OVERWRITE" ? mergeDictionaryContent({
      definitions: existing.definitions.filter((item) => item.isUserEdited),
      examples: existing.examples.filter((item) => item.isUserAdded),
    }, incoming) : mergeDictionaryContent(existing, incoming);
  }

  const result = normalizeDictionaryContent(existing);
  const force = mode === "FORCE_OVERWRITE";
  for (const field of requestedFields) {
    if (field === "pronunciations.phonetic") {
      result.pronunciations = mergePhonetic(result.pronunciations, incoming.pronunciations, force);
      continue;
    }
    if (field === "pronunciations.audio") {
      result.pronunciations = mergeAudio(result.pronunciations, incoming.pronunciations, force);
      continue;
    }
    if (field === "summary") {
      if (hasInitializationField(incoming, field)) result.summary = force ? incoming.summary : mergeDictionaryContent({ summary: result.summary }, { summary: incoming.summary }).summary;
      continue;
    }
    if (field === "learning") {
      if (hasInitializationField(incoming, field)) result.learning = force ? incoming.learning : mergeDictionaryContent({ learning: result.learning }, { learning: incoming.learning }).learning;
      continue;
    }
    if (field === "sentenceAnalysis") {
      if (hasInitializationField(incoming, field)) result.sentenceAnalysis = force ? incoming.sentenceAnalysis : mergeDictionaryContent({ sentenceAnalysis: result.sentenceAnalysis }, { sentenceAnalysis: incoming.sentenceAnalysis }).sentenceAnalysis;
      continue;
    }
    const key = field as SimpleArrayField;
    const incomingValue = incoming[key];
    if (!incomingValue.length) continue;
    if (force && key === "definitions") {
      result.definitions = mergeDictionaryContent(
        { definitions: result.definitions.filter((item) => item.isUserEdited) },
        { definitions: incoming.definitions },
      ).definitions;
      continue;
    }
    if (force && key === "examples") {
      result.examples = mergeDictionaryContent(
        { examples: result.examples.filter((item) => item.isUserAdded) },
        { examples: incoming.examples },
      ).examples;
      continue;
    }
    if (force || !result[key].length) result[key] = incomingValue as never;
  }
  return result;
}
