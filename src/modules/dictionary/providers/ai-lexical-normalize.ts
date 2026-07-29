const ENUM_MAP: Record<string, string> = {
  common: "COMMON", very_common: "VERY_COMMON", normal: "NORMAL", rare: "RARE", a1: "A1", a2: "A2", b1: "B1", b2: "B2", c1: "C1", c2: "C2",
  formal: "FORMAL", informal: "INFORMAL", neutral: "NEUTRAL", slang: "SLANG", general: "NEUTRAL", easy: "EASY", intermediate: "NORMAL", advanced: "ADVANCED", "upper-intermediate": "ADVANCED",
  lemma: "LEMMA", past: "PAST", past_participle: "PAST_PARTICIPLE", present_participle: "PRESENT_PARTICIPLE", third_person: "THIRD_PERSON", plural: "PLURAL", comparative: "COMPARATIVE", superlative: "SUPERLATIVE", other: "OTHER", prefix: "PREFIX", suffix: "SUFFIX", collocation: "COLLOCATION", phrase: "PHRASE", idiom: "IDIOM",
};
function fixEnum(value: unknown, allowed: string[]): unknown {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string" || allowed.includes(value)) return value;
  const mapped = ENUM_MAP[value.trim().toLowerCase().replace(/[\s-]+/g, "_")];
  return mapped && allowed.includes(mapped) ? mapped : value;
}
function fixRelatedItem(item: unknown): unknown {
  if (typeof item === "string") return { word: item, translation: null, partOfSpeech: null, difference: null };
  if (item && typeof item === "object") {
    const object = item as Record<string, unknown>;
    object.translation ??= null; object.partOfSpeech ??= null; object.difference ??= null; object.relation ??= "RELATED";
  }
  return item;
}
function fixCollocation(item: unknown): unknown { return typeof item === "string" ? { phrase: item, translation: null, example: null } : item; }
function fixKeyExpression(item: unknown): unknown {
  if (typeof item !== "string") return item;
  const parts = item.split(/[:：]/); return { expression: parts[0]?.trim() ?? item, meaning: parts.slice(1).join(":").trim() || item, note: null };
}

export function normalizeAiOutput(raw: unknown): unknown {
  if (!raw || typeof raw !== "object") return raw;
  const object = raw as Record<string, unknown>;
  if (object.summary && typeof object.summary === "object") { const summary = object.summary as Record<string, unknown>; summary.cefrLevel = fixEnum(summary.cefrLevel, ["A1", "A2", "B1", "B2", "C1", "C2"]); summary.frequency = fixEnum(summary.frequency, ["VERY_COMMON", "COMMON", "NORMAL", "RARE"]); }
  if (Array.isArray(object.senses)) for (const sense of object.senses as Array<Record<string, unknown>>) {
    if (!sense || typeof sense !== "object") continue;
    sense.register = fixEnum(sense.register, ["FORMAL", "INFORMAL", "NEUTRAL", "SLANG"]);
    if (Array.isArray(sense.examples)) for (const example of sense.examples as Array<Record<string, unknown>>) if (example && typeof example === "object") example.difficulty = fixEnum(example.difficulty, ["EASY", "NORMAL", "ADVANCED"]);
    if (Array.isArray(sense.synonyms)) sense.synonyms = sense.synonyms.map(fixRelatedItem);
    if (Array.isArray(sense.antonyms)) sense.antonyms = sense.antonyms.map(fixRelatedItem);
    if (Array.isArray(sense.collocations)) sense.collocations = sense.collocations.map(fixCollocation);
  }
  const morphology = object.morphology;
  if (morphology && typeof morphology === "object") {
    const value = morphology as Record<string, unknown>;
    if (Array.isArray(value.forms)) for (const form of value.forms as Array<Record<string, unknown>>) if (form && typeof form === "object") form.type = fixEnum(form.type, ["LEMMA", "PAST", "PAST_PARTICIPLE", "PRESENT_PARTICIPLE", "THIRD_PERSON", "PLURAL", "COMPARATIVE", "SUPERLATIVE", "OTHER"]);
    if (Array.isArray(value.wordFamily)) value.wordFamily = value.wordFamily.map(fixRelatedItem);
    if (Array.isArray(value.affixes)) value.affixes = value.affixes.filter(Boolean).map((item) => { const affix = item as Record<string, unknown>; affix.meaning ||= String(affix.value ?? ""); affix.type = fixEnum(affix.type, ["PREFIX", "SUFFIX"]); return affix; });
  }
  if (Array.isArray(object.phrases)) object.phrases = object.phrases.map(fixCollocation);
  if (Array.isArray(object.confusedWords)) object.confusedWords = object.confusedWords.map(fixRelatedItem);
  const sentence = object.sentenceAnalysis;
  if (sentence && typeof sentence === "object") {
    const value = sentence as Record<string, unknown>;
    value.grammarPattern ??= null; value.grammarExplanation ??= null; value.grammarNotes = Array.isArray(value.grammarNotes) ? value.grammarNotes : [];
    value.keyExpressions = Array.isArray(value.keyExpressions) ? value.keyExpressions.map(fixKeyExpression) : [];
    value.similarExamples = Array.isArray(value.similarExamples) ? value.similarExamples.map((item) => typeof item === "string" ? { sentence: item, translation: "", focus: null } : item) : [];
    value.variations = Array.isArray(value.variations) ? value.variations.map((item) => typeof item === "string" ? { sentence: item, translation: null } : item) : [];
  }
  return object;
}
