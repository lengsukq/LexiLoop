import type { AppSettings, DictionaryContent, LookupInput, RelatedWordItem } from "@/lib/types";
import type { DictionaryProvider } from "../provider";
import { fetchDictionaryUpstream } from "../proxy-fetch";

type MwEntry = {
  meta?: { id?: string; syns?: string[][]; ants?: string[][] };
  hwi?: { prs?: Array<{ mw?: string; sound?: { audio?: string } }> };
  fl?: string;
  shortdef?: string[];
  def?: Array<{ sseq?: unknown[][] }>;
};

function cleanMarkup(value: string): string {
  return value.replace(/\{[^}|]+(?:\|[^}]*)?\}/g, "").replace(/\s+/g, " ").trim();
}

function audioUrl(audio: string): string {
  const first = audio.slice(0, 1).toLowerCase();
  const folder = audio.startsWith("bix") ? "bix" : audio.startsWith("gg") ? "gg" : /[^a-z]/i.test(first) ? "number" : first;
  return `https://media.merriam-webster.com/audio/prons/en/us/mp3/${folder}/${audio}.mp3`;
}

function words(groups: string[][] | undefined, relation: string): RelatedWordItem[] {
  return [...new Set((groups ?? []).flat())].slice(0, 24).map((word) => ({ word, translation: null, partOfSpeech: null, relation, source: "merriam-webster" }));
}

function examples(entries: MwEntry[]): DictionaryContent["examples"] {
  const output: DictionaryContent["examples"] = [];
  const visit = (value: unknown): void => {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      for (const child of Object.values(value)) visit(child);
      return;
    }
    if (!Array.isArray(value)) return;
    for (const item of value) {
      if (!Array.isArray(item)) { visit(item); continue; }
      if (item[0] === "vis" && Array.isArray(item[1])) {
        for (const example of item[1]) {
          const sentence = example && typeof example === "object" ? cleanMarkup(String((example as Record<string, unknown>).t ?? "")) : "";
          if (sentence) output.push({ sentence, translation: null, source: "merriam-webster", isUserAdded: false });
        }
      } else visit(item);
    }
  };
  for (const entry of entries) visit(entry.def);
  return output.slice(0, 6);
}

async function request(reference: "collegiate" | "thesaurus", term: string, key: string): Promise<MwEntry[] | null> {
  const response = await fetchDictionaryUpstream(
    { target: "merriam-webster", term, reference, apiKey: key, timeoutMs: 10_000 },
    () => fetch(`https://www.dictionaryapi.com/api/v3/references/${reference}/json/${encodeURIComponent(term)}?key=${encodeURIComponent(key)}`, {
      signal: AbortSignal.timeout(10_000), headers: { accept: "application/json", "user-agent": "LexiLoop/1.0" },
    }),
  );
  if (response.status === 404) return null;
  if (!response.ok) throw new Error(`HTTP_${response.status}`);
  const raw = await response.text();
  let payload: unknown;
  try { payload = JSON.parse(raw); }
  catch { throw new Error(`INVALID_RESPONSE: ${raw.slice(0, 160)}`); }
  return Array.isArray(payload) ? payload.filter((item): item is MwEntry => Boolean(item && typeof item === "object" && !Array.isArray(item))) : null;
}

export class MerriamWebsterProvider implements DictionaryProvider {
  readonly id = "merriam-webster";
  constructor(private readonly settings: AppSettings) {}
  supports(input: LookupInput) { return this.settings.merriamWebsterEnabled && input.sourceLanguage === "en" && input.entryType === "WORD" && Boolean(this.settings.merriamWebsterDictionaryKey.trim() || this.settings.merriamWebsterThesaurusKey.trim()); }

  async lookup(input: LookupInput) {
    try {
      const [dictionaryResult, thesaurusResult] = await Promise.allSettled([
        this.settings.merriamWebsterDictionaryKey.trim() ? request("collegiate", input.term, this.settings.merriamWebsterDictionaryKey) : Promise.resolve(null),
        this.settings.merriamWebsterThesaurusKey.trim() ? request("thesaurus", input.term, this.settings.merriamWebsterThesaurusKey) : Promise.resolve(null),
      ]);
      if (dictionaryResult.status === "rejected" && thesaurusResult.status === "rejected") throw dictionaryResult.reason;
      const dictionary = dictionaryResult.status === "fulfilled" ? dictionaryResult.value : null;
      const thesaurus = thesaurusResult.status === "fulfilled" ? thesaurusResult.value : null;
      const definitions = (dictionary ?? []).flatMap((entry) => (entry.shortdef ?? []).map((text) => ({ language: "en", partOfSpeech: entry.fl ?? null, text: cleanMarkup(text), source: this.id, isUserEdited: false })));
      const pronunciations = (dictionary ?? []).flatMap((entry) => (entry.hwi?.prs ?? []).flatMap((item) => item.mw ? [{ accent: "US" as const, phonetic: item.mw, audioUrl: item.sound?.audio ? audioUrl(item.sound.audio) : null, source: this.id, isSynthetic: false }] : []));
      const synonyms = words((thesaurus ?? []).flatMap((entry) => entry.meta?.syns ?? []), "SYNONYM");
      const antonyms = words((thesaurus ?? []).flatMap((entry) => entry.meta?.ants ?? []), "ANTONYM");
      const content: Partial<DictionaryContent> = { definitions, pronunciations, examples: examples(dictionary ?? []), synonyms, antonyms };
      return definitions.length || synonyms.length || antonyms.length ? { content } : { content: null, errorCode: "NOT_FOUND", errorMessage: "Merriam-Webster 中没有该词条" };
    } catch (error) {
      const timeout = error instanceof DOMException && error.name === "TimeoutError";
      return { content: null, errorCode: timeout ? "TIMEOUT" : "NETWORK_ERROR", errorMessage: String(error), transient: true };
    }
  }
}
