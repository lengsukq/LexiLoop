import { migrateDatabase } from "../src/db/migrate";
import Database from "better-sqlite3";

const databasePath = "./data/repro.sqlite";
migrateDatabase(databasePath);
const sqlite = new Database(databasePath);
sqlite.pragma("journal_mode = WAL");
sqlite.pragma("foreign_keys = ON");

const now = Date.now();

function insertWord(term: string, definition: string): number {
  const result = sqlite
    .prepare(
      `INSERT INTO words
       (term, normalized_term, source_language, target_language, entry_type, content_type, initialization_status, created_at, updated_at)
       VALUES (?, ?, 'en', 'zh-CN', 'WORD', 'WORD', 'READY', ?, ?)`,
    )
    .run(term, term, now, now);
  const wordId = Number(result.lastInsertRowid);
  sqlite
    .prepare(
      `INSERT INTO word_contents
       (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json,
        synonyms_json, antonyms_json, tags_json, provider_metadata_json, updated_at)
       VALUES (?, ?, '[]', '[]', '[]', '[]', '[]', '[]', '[]', '[]', ?)`,
    )
    .run(
      wordId,
      JSON.stringify([{ language: "zh-CN", partOfSpeech: "n.", text: definition, source: "repro", isUserEdited: false }]),
      now,
    );
  return wordId;
}

const longDefinition =
  "极其冗长的一个释义，用来复现答题界面内容超长时无法滚动的问题。" +
  "这句话特意写得非常非常长，长到足以把下方的四个选项按钮完全挤出可视区域之外，" +
  "这样用户就看不到也点不到任何选项了。" +
  "再加上更多的填充文字，确保无论屏幕高度是多少，这四个选项都会被推到底部折叠区域以下，" +
  "从而在无法滚动的情况下完全无法操作。" +
  "重复一遍：极其冗长的一个释义，用来复现答题界面内容超长时无法滚动的问题。" +
  "这句话特意写得非常非常长，长到足以把下方的四个选项按钮完全挤出可视区域之外。" +
  "这样用户就看不到也点不到任何选项了。" +
  "再加上更多的填充文字，确保无论屏幕高度是多少，这四个选项都会被推到底部折叠区域以下。" +
  "重复第二遍：极其冗长的一个释义，用来复现答题界面内容超长时无法滚动的问题。" +
  "这句话特意写得非常非常长，长到足以把下方的四个选项按钮完全挤出可视区域之外。" +
  "这样用户就看不到也点不到任何选项了。" +
  "再加上更多的填充文字，确保无论屏幕高度是多少，这四个选项都会被推到底部折叠区域以下。" +
  "现在释义已经足够长了。";

insertWord("overwhelmingly", longDefinition);
insertWord("phenomenon", "一个普通长度的释义：现象、非凡的人或事物。");

console.log("[repro] seeded words into", databasePath);
sqlite.close();
