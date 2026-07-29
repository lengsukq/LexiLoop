import Database from "better-sqlite3";
import fs from "node:fs";
import path from "node:path";
import type { DictionaryProvider } from "../provider";
import type { LookupInput, WordFormItem } from "@/lib/types";

let cache: { path: string; mtimeMs: number; db: Database.Database } | null = null;

function getDatabase(): Database.Database | null {
  const databasePath = path.resolve(process.env.ECDICT_DATABASE_PATH ?? "./data/reference/ecdict.sqlite");
  if (!fs.existsSync(databasePath)) return null;
  const mtimeMs = fs.statSync(databasePath).mtimeMs;
  if (cache?.path === databasePath && cache.mtimeMs === mtimeMs) return cache.db;
  cache?.db.close();
  cache = { path: databasePath, mtimeMs, db: new Database(databasePath, { readonly: true, fileMustExist: true }) };
  return cache.db;
}

const formMap: Record<string, WordFormItem["type"]> = {
  "0": "LEMMA", "1": "LEMMA", p: "PAST", d: "PAST", i: "PAST_PARTICIPLE",
  g: "PRESENT_PARTICIPLE", v: "PRESENT_PARTICIPLE", "3": "THIRD_PERSON", s: "PLURAL",
  r: "COMPARATIVE", t: "SUPERLATIVE",
};

export class EcdictProvider implements DictionaryProvider {
  readonly id = "ecdict";
  supports(input: LookupInput) { return input.sourceLanguage === "en"; }

  async lookup(input: LookupInput) {
    const database = getDatabase();
    if (!database) return { content: null, errorCode: "DATABASE_UNAVAILABLE", errorMessage: "ECDICT 未安装" };
    try {
      const row = database.prepare(`SELECT word, phonetic, translation, pos, tag, exchange, audio
        FROM stardict WHERE lower(word) = lower(?) LIMIT 1`).get(input.normalizedTerm) as {
          word: string; phonetic: string | null; translation: string | null; pos: string | null;
          tag: string | null; exchange: string | null; audio: string | null;
        } | undefined;
      if (!row) return { content: null, errorCode: "NOT_FOUND", errorMessage: "ECDICT 中没有该词条" };
      const definitions = (row.translation ?? "").split(/\\n|\n/).map((value) => value.trim()).filter(Boolean).map((text) => ({
        language: "zh-CN", partOfSpeech: row.pos?.split("/").filter(Boolean)[0] ?? null,
        text, source: this.id, isUserEdited: false,
      }));
      const pronunciations = [];
      if (row.phonetic) pronunciations.push({ accent: "US" as const, phonetic: row.phonetic, audioUrl: null, source: this.id, isSynthetic: false });
      for (const audioUrl of (row.audio ?? "").split(",").map((value) => value.trim()).filter(Boolean)) {
        const marker = audioUrl.toLowerCase();
        pronunciations.push({ accent: marker.includes("uk") ? "UK" as const : "US" as const, phonetic: row.phonetic, audioUrl, source: this.id, isSynthetic: false });
      }
      const forms = (row.exchange ?? "").split("/").map((value) => {
        const [code, ...rest] = value.split(":");
        const form = rest.join(":").trim();
        return code && form ? { type: formMap[code] ?? "OTHER" as const, value: form, source: this.id } : null;
      }).filter((value): value is NonNullable<typeof value> => value !== null);
      return { content: { definitions, pronunciations, forms, tags: (row.tag ?? "").split(/\s+/).filter(Boolean) } };
    } catch (error) {
      return { content: null, errorCode: "DATABASE_ERROR", errorMessage: String(error), transient: true };
    }
  }
}
