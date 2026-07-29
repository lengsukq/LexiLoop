import type { DictionaryContent, EntryType } from "@/lib/types";
import { parseDefinitions, parseExamples, parsePhrases, parsePhonetics, parseTranslation, parseWordForms } from "./youdao-fields";

export interface YoudaoParseOptions {
  term: string;
  entryType: EntryType;
  targetLanguage: string;
}

function decodeEntities(value: string): string {
  return value
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#x([0-9a-f]+);/gi, (_match, code) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&#(\d+);/g, (_match, code) => String.fromCodePoint(Number(code)));
}

function extractTextLines(html: string): string[] {
  let text = html
    .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "")
    .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "")
    .replace(/<noscript[^>]*>[\s\S]*?<\/noscript>/gi, "");
  text = text
    .replace(/<br\s*\/?\s*>/gi, "\n")
    .replace(/<\/(div|p|li|ul|ol|h[1-6]|section|article|tr|td|th|dl|dt|dd|blockquote|pre)[^>]*>/gi, "\n")
    .replace(/<(div|p|li|ul|ol|h[1-6]|section|article|tr|td|th|dl|dt|dd|blockquote|pre)[^>]*>/gi, "\n")
    .replace(/<[^>]+>/g, "");
  return decodeEntities(text)
    .replace(/\*\*/g, "")
    .split("\n")
    .map((line) => line.replace(/\s+/g, " ").trim())
    .filter(Boolean);
}

function parseTags(lines: string[]): string[] {
  const levelLine = lines.find((line) => /(?:初中|高中|CET4|CET6|考研|四级|六级)/.test(line));
  if (!levelLine) return [];
  return [...new Set(levelLine.split(/[\/、，,\s]+/).map((value) => value.trim()).filter((value) => /^(初中|高中|CET4|CET6|考研|四级|六级)$/.test(value)))];
}

export function hasAnyContent(content: Partial<DictionaryContent>): boolean {
  return Boolean(
    content.definitions?.length
      || content.pronunciations?.length
      || content.forms?.length
      || content.examples?.length
      || content.phrases?.length
      || content.summary?.translation?.trim()
      || content.summary?.shortDefinition?.trim(),
  );
}

export function parseYoudaoHtml(html: string, optionsOrTerm: YoudaoParseOptions | string): Partial<DictionaryContent> | null {
  const options: YoudaoParseOptions = typeof optionsOrTerm === "string"
    ? { term: optionsOrTerm, entryType: "WORD", targetLanguage: "zh-CN" }
    : optionsOrTerm;
  const lines = extractTextLines(html);
  if (!lines.length) return null;

  const translation = parseTranslation(lines, options.term, options.targetLanguage);
  const definitions = parseDefinitions(lines, options.targetLanguage);
  const examples = parseExamples(lines, options.term);
  const phrases = parsePhrases(lines);
  const content: Partial<DictionaryContent> = {
    pronunciations: options.entryType === "WORD" ? parsePhonetics(lines) : [],
    definitions,
    forms: options.entryType === "WORD" ? parseWordForms(lines) : [],
    examples,
    phrases,
    tags: parseTags(lines),
  };

  if (translation) {
    content.summary = {
      shortDefinition: null,
      translation: translation.translation,
      cefrLevel: null,
      frequency: null,
    };
    if (options.entryType !== "WORD") {
      content.definitions = [
        { language: options.targetLanguage, partOfSpeech: null, text: translation.translation, source: translation.source, isUserEdited: false },
        ...(content.definitions ?? []),
      ];
      content.examples = [
        { sentence: options.term, translation: translation.translation, source: translation.source, isUserAdded: false },
        ...(content.examples ?? []),
      ];
      if (options.entryType === "PHRASE") {
        content.phrases = [
          { phrase: options.term, translation: translation.translation, source: translation.source },
          ...(content.phrases ?? []),
        ];
      }
    }
  }

  return content;
}
