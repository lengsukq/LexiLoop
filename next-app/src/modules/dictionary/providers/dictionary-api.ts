import type { DictionaryProvider } from "../provider";
import { fetchDictionaryUpstream } from "../proxy-fetch";
import type { DictionaryContent, LookupInput } from "@/lib/types";

interface ApiEntry {
  phonetic?: string;
  phonetics?: Array<{ text?: string; audio?: string; sourceUrl?: string }>;
  meanings?: Array<{
    partOfSpeech?: string;
    synonyms?: string[];
    antonyms?: string[];
    definitions?: Array<{ definition?: string; example?: string; synonyms?: string[]; antonyms?: string[] }>;
  }>;
}

export class DictionaryApiProvider implements DictionaryProvider {
  readonly id = "dictionaryapi.dev";
  supports(input: LookupInput) { return input.sourceLanguage === "en" && input.entryType === "WORD"; }

  async lookup(input: LookupInput) {
    try {
      const response = await fetchDictionaryUpstream(
        { target: "dictionaryapi", term: input.term, timeoutMs: 10_000 },
        () => fetch(`https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(input.term)}`, {
          signal: AbortSignal.timeout(10_000),
          headers: { accept: "application/json", "user-agent": "LexiLoop/1.0" },
        }),
      );
      if (response.status === 404) return { content: null, errorCode: "NOT_FOUND", errorMessage: "词典中没有该词条" };
      if (response.status === 429) return { content: null, errorCode: "RATE_LIMITED", errorMessage: "词典 API 限流", transient: true };
      if (!response.ok) return { content: null, errorCode: `HTTP_${response.status}`, errorMessage: `词典 API 返回 ${response.status}`, transient: response.status >= 500 };
      const entries = await response.json() as ApiEntry[];
      const content: Partial<DictionaryContent> = { definitions: [], pronunciations: [], examples: [], synonyms: [], antonyms: [], tags: [] };
      for (const entry of entries.slice(0, 2)) {
        for (const phonetic of entry.phonetics ?? []) {
          if (!phonetic.text && !phonetic.audio) continue;
          const marker = `${phonetic.audio ?? ""} ${phonetic.sourceUrl ?? ""}`.toLowerCase();
          content.pronunciations?.push({
            accent: marker.includes("uk") ? "UK" : "US",
            phonetic: phonetic.text ?? entry.phonetic ?? null,
            audioUrl: phonetic.audio || null,
            source: this.id,
            isSynthetic: false,
          });
        }
        for (const meaning of entry.meanings ?? []) {
          for (const definition of meaning.definitions ?? []) {
            if (!definition.definition) continue;
            content.definitions?.push({ language: "en", partOfSpeech: meaning.partOfSpeech ?? null, text: definition.definition, source: this.id, isUserEdited: false });
            if (definition.example) content.examples?.push({ sentence: definition.example, translation: null, source: this.id, isUserAdded: false });
            content.synonyms?.push(...(definition.synonyms ?? []).map((word) => ({ word, translation: null, partOfSpeech: meaning.partOfSpeech ?? null, relation: "SYNONYM", source: this.id })));
            content.antonyms?.push(...(definition.antonyms ?? []).map((word) => ({ word, translation: null, partOfSpeech: meaning.partOfSpeech ?? null, relation: "ANTONYM", source: this.id })));
          }
          content.synonyms?.push(...(meaning.synonyms ?? []).map((word) => ({ word, translation: null, partOfSpeech: meaning.partOfSpeech ?? null, relation: "SYNONYM", source: this.id })));
          content.antonyms?.push(...(meaning.antonyms ?? []).map((word) => ({ word, translation: null, partOfSpeech: meaning.partOfSpeech ?? null, relation: "ANTONYM", source: this.id })));
        }
      }
      return content.definitions?.length ? { content } : { content: null, errorCode: "EMPTY_RESULT", errorMessage: "词典返回空内容" };
    } catch (error) {
      const timeout = error instanceof DOMException && error.name === "TimeoutError";
      return { content: null, errorCode: timeout ? "TIMEOUT" : "NETWORK_ERROR", errorMessage: String(error), transient: true };
    }
  }
}
