import type { DictionaryContent } from "@/lib/types";
import { parseDefinitions, parseExamples, parsePhrases, parsePhonetics, parseWordForms } from "./youdao-fields";

function extractTextLines(html: string): string[] {
  let text = html.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "").replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "").replace(/<noscript[^>]*>[\s\S]*?<\/noscript>/gi, "");
  text = text.replace(/<br\s*\/?\s*>/gi, "\n").replace(/<\/(div|p|li|ul|ol|h[1-6]|section|article|tr|td|th|dl|dt|dd|blockquote|pre)[^>]*>/gi, "\n").replace(/<(div|p|li|ul|ol|h[1-6]|section|article|tr|td|th|dl|dt|dd|blockquote|pre)[^>]*>/gi, "\n").replace(/<[^>]+>/g, "");
  return text.replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#(\d+);/g, (_match, code) => String.fromCodePoint(Number(code))).replace(/\*\*/g, "").split("\n").map((line) => line.trim()).filter(Boolean);
}

export function hasAnyContent(content: Partial<DictionaryContent>): boolean {
  return Boolean(content.definitions?.length || content.pronunciations?.length || content.forms?.length || content.examples?.length || content.phrases?.length);
}
export function parseYoudaoHtml(html: string, term: string): Partial<DictionaryContent> | null {
  const lines = extractTextLines(html); if (!lines.length) return null;
  return { pronunciations: parsePhonetics(lines), definitions: parseDefinitions(lines), forms: parseWordForms(lines), examples: parseExamples(lines, term), phrases: parsePhrases(lines), tags: [] };
}
