import type { DictionaryContent } from "@/lib/types";
import {
  parseIcibaConfusedWords,
  parseIcibaDefinitions,
  parseIcibaExamples,
  parseIcibaForms,
  parseIcibaPhonetics,
  parseIcibaPhrases,
  parseIcibaRoots,
  parseIcibaSummary,
  parseIcibaSynonyms,
  parseIcibaTags,
  type IcibaWordInfo,
} from "./iciba-fields";

export function extractIcibaWordInfo(html: string): IcibaWordInfo | null {
  const match = html.match(/<script id="__NEXT_DATA__"[^>]*>(.*?)<\/script>/s);
  if (!match?.[1]) return null;
  try {
    const data = JSON.parse(match[1]);
    const info = data?.props?.pageProps?.initialReduxState?.word?.wordInfo;
    if (!info || typeof info !== "object") return null;
    return info as IcibaWordInfo;
  } catch {
    return null;
  }
}

export function hasAnyIcibaContent(content: Partial<DictionaryContent>): boolean {
  return Boolean(
    content.definitions?.length
    || content.pronunciations?.length
    || content.forms?.length
    || content.examples?.length
    || content.phrases?.length
    || content.synonyms?.length
    || content.wordFamily?.length
    || content.roots?.length
    || content.confusedWords?.length
    || content.summary?.shortDefinition?.trim()
    || content.summary?.frequency
    || content.tags?.length,
  );
}

export function parseIcibaHtml(html: string, options: { term: string; targetLanguage: string }): Partial<DictionaryContent> | null {
  const info = extractIcibaWordInfo(html);
  if (!info) return null;

  const definitions = parseIcibaDefinitions(info, options.targetLanguage);
  if (!definitions.length && !info.baesInfo?.symbols?.length) return null;

  const content: Partial<DictionaryContent> = {
    definitions,
    pronunciations: parseIcibaPhonetics(info),
    forms: parseIcibaForms(info),
    examples: parseIcibaExamples(info),
    phrases: parseIcibaPhrases(info),
    synonyms: parseIcibaSynonyms(info),
    wordFamily: [],
    roots: parseIcibaRoots(info),
    confusedWords: parseIcibaConfusedWords(info),
    summary: parseIcibaSummary(info),
    tags: parseIcibaTags(info),
  };

  if (!hasAnyIcibaContent(content)) return null;
  return content;
}
