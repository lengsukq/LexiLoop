import { sqlite } from "@/db/client";
import type { DictionaryContent } from "@/lib/types";

export interface SaveWordContentOptions {
  /** 不传时不写 `content_source` 列（沿用表默认 'MIXED'），与历史手动/初始化落库行为一致。 */
  contentSource?: string | null;
  /** 写入 `provider_metadata_json` 的值（默认空数组）。 */
  providerMetadata?: unknown;
  /** 不传时使用 `Date.now()`。 */
  now?: number;
}

/**
 * 单一 `word_contents` upsert 出口，消除 4+ 处全字段复制。
 * 17 个 JSON 列按固定顺序写入，并在冲突时同步更新；`content_version` 自增、`initialized_at`/`updated_at` 置为 now。
 */
export async function saveWordContent(wordId: number, content: DictionaryContent, options: SaveWordContentOptions = {}): Promise<void> {
  const now = options.now ?? Date.now();
  const providerMetadata = options.providerMetadata ?? [];

  const jsonFields: Array<[string, unknown]> = [
    ["definitions_json", content.definitions],
    ["pronunciations_json", content.pronunciations],
    ["examples_json", content.examples],
    ["phrases_json", content.phrases],
    ["forms_json", content.forms],
    ["synonyms_json", content.synonyms],
    ["antonyms_json", content.antonyms],
    ["word_family_json", content.wordFamily],
    ["confused_words_json", content.confusedWords],
    ["roots_json", content.roots],
    ["affixes_json", content.affixes],
    ["summary_json", content.summary],
    ["learning_json", content.learning],
    ["sentence_analysis_json", content.sentenceAnalysis],
    ["tags_json", content.tags],
    ["provider_metadata_json", providerMetadata],
  ];

  const extraColumn = options.contentSource !== undefined ? ["content_source"] : [];
  const extraValue = options.contentSource !== undefined ? [options.contentSource] : [];
  const extraConflict = options.contentSource !== undefined ? ["content_source = excluded.content_source"] : [];

  const columns = [...jsonFields.map(([name]) => name), ...extraColumn, "content_version", "initialized_at", "updated_at"];
  const conflictSet = [
    ...jsonFields.map(([name]) => `${name} = excluded.${name}`),
    ...extraConflict,
    "content_version = word_contents.content_version + 1",
    "initialized_at = excluded.initialized_at",
    "updated_at = excluded.updated_at",
  ];

  const placeholders = columns.map(() => "?").join(", ");
  const values = [...jsonFields.map(([, value]) => JSON.stringify(value)), ...extraValue.map((value) => value), 1, now, now];

  await sqlite.prepare(`INSERT INTO word_contents
    (word_id, ${columns.join(", ")})
    VALUES (?, ${placeholders})
    ON CONFLICT(word_id) DO UPDATE SET ${conflictSet.join(", ")}`)
    .run(wordId, ...values);
}
