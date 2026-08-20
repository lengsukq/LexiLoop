import { sqlite } from "@/db/client";

/**
 * 词条存在非空释义文本时才可学习/推荐，避免出现无选项的释义题。
 * 同时兼容 Postgres（`json_array_elements` + `::json`）与 SQLite（`json_each` + `json_valid`）。
 */
export function definitionMeaningSql(): string {
  return sqlite.mode === "postgres"
    ? `EXISTS (SELECT 1 FROM word_contents wc WHERE wc.word_id = w.id AND json_typeof(wc.definitions_json::json) = 'array' AND EXISTS (SELECT 1 FROM json_array_elements(wc.definitions_json::json) d WHERE btrim(d->>'text') <> ''))`
    : `EXISTS (SELECT 1 FROM word_contents wc, json_each(wc.definitions_json) d WHERE wc.word_id = w.id AND json_valid(wc.definitions_json) AND trim(json_extract(d.value, '$.text')) <> '')`;
}

/** 句子类词条也可把含义放在 `summary.translation` 里。 */
export function summaryTranslationSql(): string {
  return sqlite.mode === "postgres"
    ? `EXISTS (SELECT 1 FROM word_contents wc WHERE wc.word_id = w.id AND json_typeof(wc.summary_json::json) = 'object' AND btrim(wc.summary_json::json->>'translation') <> '')`
    : `EXISTS (SELECT 1 FROM word_contents wc WHERE wc.word_id = w.id AND json_valid(wc.summary_json) AND trim(json_extract(wc.summary_json, '$.translation')) <> '')`;
}
