/** 词条存在非空释义文本时才可学习/推荐，避免出现无选项的释义题。 */
export function definitionMeaningSql(): string {
  return `EXISTS (SELECT 1 FROM word_contents wc WHERE wc.word_id = w.id AND json_typeof(wc.definitions_json::json) = 'array' AND EXISTS (SELECT 1 FROM json_array_elements(wc.definitions_json::json) d WHERE btrim(d->>'text') <> ''))`;
}

/** 句子类词条也可把含义放在 `summary.translation` 里。 */
export function summaryTranslationSql(): string {
  return `EXISTS (SELECT 1 FROM word_contents wc WHERE wc.word_id = w.id AND json_typeof(wc.summary_json::json) = 'object' AND btrim(wc.summary_json::json->>'translation') <> '')`;
}
