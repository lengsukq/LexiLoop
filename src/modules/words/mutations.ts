import { sqlite } from "@/db/client";
import { z } from "zod";
import type { DictionaryContent, EntryType } from "@/lib/types";
import { contentStatus, dictionaryContentFromRow, emptyDictionaryContent } from "@/modules/dictionary/content";
import { closeStudySessionWithActiveDuration } from "@/modules/reviews/duration";
import { getWordDetail } from "./queries";

async function cancelPendingStudyItemsForSuspend(wordId: number, now: number): Promise<void> {
  const sessions = await sqlite.prepare(`SELECT study_session_id AS session_id, count(*) AS count
    FROM study_session_items WHERE word_id = ? AND status = 'PENDING' GROUP BY study_session_id`).all(wordId) as Array<{ session_id: number; count: number }>;
  await sqlite.prepare(`UPDATE study_session_items SET status = 'SKIPPED', answered_at = ?, skip_reason = 'WORD_SUSPENDED'
    WHERE word_id = ? AND status = 'PENDING'`).run(now, wordId);
  for (const session of sessions) {
    await sqlite.prepare(`UPDATE study_sessions SET completed_count = completed_count + ?, skipped_count = skipped_count + ? WHERE id = ?`)
      .run(session.count, session.count, session.session_id);
    const pending = await sqlite.prepare("SELECT count(*) AS count FROM study_session_items WHERE study_session_id = ? AND status = 'PENDING'")
      .get(session.session_id) as { count: number };
    if (pending.count === 0) await closeStudySessionWithActiveDuration(session.session_id, now);
  }
}

const updateSchema = z.object({
  userNote: z.string().max(5000).nullable().optional(),
  isSuspended: z.boolean().optional(),
}).strict();

export async function updateWord(wordId: number, input: unknown) {
  const values = updateSchema.parse(input);
  if (!await sqlite.prepare("SELECT id FROM words WHERE id = ?").get(wordId)) throw new Error("WORD_NOT_FOUND");
  const updates: string[] = [];
  const params: Array<string | number | null> = [];
  if (values.userNote !== undefined) { updates.push("user_note = ?"); params.push(values.userNote); }
  if (values.isSuspended !== undefined) { updates.push("is_suspended = ?"); params.push(values.isSuspended ? 1 : 0); }
  if (updates.length) {
    updates.push("updated_at = ?");
    params.push(Date.now(), wordId);
    await sqlite.prepare(`UPDATE words SET ${updates.join(", ")} WHERE id = ?`).run(...params);
  }
  if (values.isSuspended) await cancelPendingStudyItemsForSuspend(wordId, Date.now());
  return getWordDetail(wordId);
}

const manualDefinitionSchema = z.object({
  definition: z.string().trim().max(2000),
  partOfSpeech: z.string().trim().max(50).nullable().optional(),
}).strict();

export async function updateManualDefinition(wordId: number, input: unknown) {
  const values = manualDefinitionSchema.parse(input);
  const word = await sqlite.prepare("SELECT id, target_language, content_type FROM words WHERE id = ?").get(wordId) as {
    id: number; target_language: string; content_type: EntryType;
  } | undefined;
  if (!word) throw new Error("WORD_NOT_FOUND");
  const row = await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(wordId) as Record<string, unknown> | undefined;
  const content: DictionaryContent = row ? dictionaryContentFromRow(row) : emptyDictionaryContent();
  content.definitions = content.definitions.filter((item) => !(item.source === "user" && item.isUserEdited));
  if (values.definition) content.definitions.unshift({ language: word.target_language, partOfSpeech: values.partOfSpeech || null, text: values.definition, source: "user", isUserEdited: true });
  const status = contentStatus(content, word.content_type);
  const now = Date.now();
  await sqlite.transaction(async () => {
    await sqlite.prepare(`INSERT INTO word_contents
      (word_id, definitions_json, pronunciations_json, examples_json, phrases_json, forms_json, synonyms_json, antonyms_json,
       word_family_json, confused_words_json, roots_json, affixes_json, summary_json, learning_json, sentence_analysis_json,
       tags_json, provider_metadata_json, content_version, initialized_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]', 1, ?, ?)
      ON CONFLICT(word_id) DO UPDATE SET definitions_json = excluded.definitions_json,
      content_version = word_contents.content_version + 1, initialized_at = excluded.initialized_at, updated_at = excluded.updated_at`)
      .run(wordId, JSON.stringify(content.definitions), JSON.stringify(content.pronunciations), JSON.stringify(content.examples), JSON.stringify(content.phrases), JSON.stringify(content.forms), JSON.stringify(content.synonyms), JSON.stringify(content.antonyms), JSON.stringify(content.wordFamily), JSON.stringify(content.confusedWords), JSON.stringify(content.roots), JSON.stringify(content.affixes), JSON.stringify(content.summary), JSON.stringify(content.learning), JSON.stringify(content.sentenceAnalysis), JSON.stringify(content.tags), now, now);
    await sqlite.prepare("UPDATE words SET initialization_status = ?, updated_at = ? WHERE id = ?").run(status, now, wordId);
  }).immediate();
  return getWordDetail(wordId);
}

const exampleIndexSchema = z.object({ index: z.number().int().nonnegative() }).strict();

export async function deleteExample(wordId: number, input: unknown) {
  const { index } = exampleIndexSchema.parse(input);
  const row = await sqlite.prepare("SELECT * FROM word_contents WHERE word_id = ?").get(wordId) as Record<string, unknown> | undefined;
  if (!row) throw new Error("EXAMPLE_NOT_FOUND");
  const content = dictionaryContentFromRow(row);
  if (!content.examples[index]) throw new Error("EXAMPLE_NOT_FOUND");
  content.examples.splice(index, 1);
  await sqlite.prepare("UPDATE word_contents SET examples_json = ?, content_version = content_version + 1, updated_at = ? WHERE word_id = ?")
    .run(JSON.stringify(content.examples), Date.now(), wordId);
  return getWordDetail(wordId);
}
