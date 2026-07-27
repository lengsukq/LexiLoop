import type { EntryType } from "@/lib/types";

const LOWERCASE_LANGUAGES = new Set(["en", "nl", "fr", "de", "es", "it", "pt", "sv", "da", "no"]);

export function normalizeTerm(term: string, languageCode: string): string {
  const normalized = term.normalize("NFKC").trim().replace(/\s+/g, " ");
  return LOWERCASE_LANGUAGES.has(languageCode)
    ? normalized.toLocaleLowerCase(languageCode === "en" ? "en-US" : languageCode)
    : normalized;
}

export function detectEntryType(term: string): EntryType {
  const trimmed = term.normalize("NFKC").trim().replace(/\s+/g, " ");
  const tokens = trimmed.split(" ").filter(Boolean);
  if (tokens.length <= 1) return "WORD";
  const hasSentencePunctuation = /[.!?。！？]$/.test(trimmed);
  const looksLikeClause = /^(i|you|he|she|it|we|they|this|that|there|who|what|where|when|why|how|please|can|could|would|should|do|does|did|is|are|was|were|have|has|had)\b/i.test(trimmed);
  return hasSentencePunctuation || tokens.length >= 6 || (tokens.length >= 4 && looksLikeClause)
    ? "SENTENCE"
    : "PHRASE";
}

export function legacyEntryType(contentType: EntryType): "WORD" | "PHRASE" {
  return contentType === "WORD" ? "WORD" : "PHRASE";
}

export function identityKey(normalizedTerm: string, sourceLanguage: string, targetLanguage: string): string {
  return `${normalizedTerm}\u0000${sourceLanguage}\u0000${targetLanguage}`;
}
