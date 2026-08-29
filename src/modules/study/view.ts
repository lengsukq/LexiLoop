import { sqlite } from "@/db/client";
import { ApiError } from "@/lib/api";
import type { DictionaryContent, EntryType, QuestionType, StudyItemView } from "@/lib/types";
import { dictionaryContentFromRow, emptyDictionaryContent, preferredDefinitionText, targetDefinitionTexts } from "@/modules/dictionary/content";

const DISTRACTOR_POOL_SIZE = 80;
const DISTRACTOR_TAKE_SIZE = 12;

interface DistractorRow {
  word_id: number;
  term: string;
  definitions_json: string;
}

let distractorPool: DistractorRow[] = [];

/** Refills the module-level distractor pool with one randomized query. */
async function refillDistractorPool(): Promise<void> {
  distractorPool = await sqlite.prepare(`SELECT w.id AS word_id, w.term, c.definitions_json
    FROM word_contents c JOIN words w ON w.id = c.word_id
    WHERE w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
      AND c.definitions_json IS NOT NULL AND c.definitions_json != '[]'
    ORDER BY RANDOM() LIMIT ?`).all(DISTRACTOR_POOL_SIZE) as DistractorRow[];
}

/**
 * Returns distractor candidates without running a RANDOM()-ordered query per
 * question. Pulls from the cached pool and refills it in bulk when depleted.
 */
async function takeDistractorRows(excludedWordIds: ReadonlySet<number>, count: number): Promise<DistractorRow[]> {
  if (distractorPool.length < count * 2) await refillDistractorPool();
  const collect = (pool: DistractorRow[]): DistractorRow[] => {
    const rows: DistractorRow[] = [];
    for (const row of pool) {
      if (excludedWordIds.has(row.word_id)) continue;
      rows.push(row);
      if (rows.length >= count) break;
    }
    return rows;
  };
  const firstPass = collect(distractorPool);
  if (firstPass.length >= count) return firstPass;
  // Rare exhaustion: refill once more before giving up.
  await refillDistractorPool();
  const secondPass = collect(distractorPool);
  return secondPass.length >= firstPass.length ? secondPass : firstPass;
}

export async function getStudySession(sessionId: number, resumed = false) {
  const session = await sqlite.prepare("SELECT * FROM study_sessions WHERE id = ?").get(sessionId) as Record<string, unknown> | undefined;
  if (!session) throw new ApiError("SESSION_NOT_FOUND");
  const rows = await sqlite.prepare(`SELECT i.id AS item_id, i.position, i.task_type, i.question_type, i.status, i.skip_reason, w.id AS word_id, w.term, w.source_language, w.target_language, w.content_type, c.definitions_json, c.pronunciations_json, c.examples_json, c.phrases_json, c.forms_json, c.synonyms_json, c.antonyms_json, c.word_family_json, c.confused_words_json, c.roots_json, c.affixes_json, c.summary_json, c.learning_json, c.sentence_analysis_json, c.tags_json FROM study_session_items i JOIN words w ON w.id = i.word_id LEFT JOIN word_contents c ON c.word_id = w.id WHERE i.study_session_id = ? ORDER BY i.position ASC`).all(sessionId) as Array<Record<string, unknown>>;
  const items = await Promise.all(rows.map(async (row) => {
    const questionType = row.question_type as QuestionType; const content = row.definitions_json === null ? emptyDictionaryContent() : dictionaryContentFromRow(row);
    const item = { itemId: Number(row.item_id), position: Number(row.position), taskType: row.task_type as StudyItemView["taskType"], questionType, status: String(row.status), skipReason: row.skip_reason === null ? null : String(row.skip_reason), word: { id: Number(row.word_id), term: String(row.term), sourceLanguage: String(row.source_language), targetLanguage: String(row.target_language), entryType: row.content_type as EntryType, content } } as StudyItemView & { status: string; skipReason: string | null };
    if (questionType === "EN_TO_ZH_CHOICE") item.choices = await generateMeaningChoices(Number(row.word_id), String(row.target_language), content);
    if (questionType === "ZH_TO_EN_CHOICE" || questionType === "LISTENING_CHOICE") {
      const payload = await generateWordChoices(Number(row.word_id), String(row.term), String(row.target_language), content);
      item.choices = payload.choices;
      item.choiceDefinitions = payload.choiceDefinitions;
    }
    if (questionType === "CLOZE_SENTENCE") {
      item.cloze = buildClozeExtra(String(row.term), content);
    }
    if (questionType === "LETTER_BANK") {
      item.letters = buildLetterTiles(String(row.term));
    }
    return item;
  }));
  const resumeIndex = items.findIndex((item) => item.status === "PENDING");
  return { resumed, resumeIndex: resumeIndex === -1 ? items.length : resumeIndex, session: { id: Number(session.id), sessionType: session.source_type === "AI_RECOMMENDED" || session.source_type === "SENTENCE_REVIEW" ? String(session.source_type) : String(session.session_type), startedAt: new Date(Number(session.started_at)).toISOString(), completedAt: session.completed_at ? new Date(Number(session.completed_at)).toISOString() : null, plannedCount: Number(session.planned_count), completedCount: Number(session.completed_count), correctCount: Number(session.correct_count), wrongCount: Number(session.wrong_count), skippedCount: Number(session.skipped_count ?? 0), durationMs: session.duration_ms === null ? null : Number(session.duration_ms) }, items };
}

function shuffle<T>(items: T[]): T[] {
  for (let index = items.length - 1; index > 0; index--) {
    const other = Math.floor(Math.random() * (index + 1));
    [items[index], items[other]] = [items[other]!, items[index]!];
  }
  return items;
}

async function findSpecificDistractorRows(terms: string[], excludedId: number): Promise<DistractorRow[]> {
  if (!terms.length) return [];
  return await sqlite.prepare(`SELECT w.id AS word_id, w.term, c.definitions_json
    FROM words w JOIN word_contents c ON c.word_id = w.id
    WHERE w.term IN (${terms.map(() => "?").join(",")}) AND w.id != ?
      AND c.definitions_json IS NOT NULL AND c.definitions_json != '[]'
    LIMIT 6`).all(...terms, excludedId) as DistractorRow[];
}

async function findActiveWrongDistractorRows(excludedId: number): Promise<DistractorRow[]> {
  return await sqlite.prepare(`SELECT w.id AS word_id, w.term, c.definitions_json
    FROM wrong_word_states x JOIN words w ON w.id = x.word_id JOIN word_contents c ON c.word_id = w.id
    WHERE x.active = 1 AND w.id != ? AND w.is_suspended = 0
      AND c.definitions_json IS NOT NULL AND c.definitions_json != '[]'
    ORDER BY x.wrong_count DESC LIMIT 8`).all(excludedId) as DistractorRow[];
}

async function generateMeaningChoices(wordId: number, targetLanguage: string, content: DictionaryContent): Promise<string[]> {
  const definitions = targetDefinitionTexts(content.definitions, targetLanguage);
  const correct = definitions; if (!correct) return [];

  const distractors: string[] = [];
  const seen = new Set([correct.toLocaleLowerCase()]);

  // 1. 优先提取易混词 (Confused words) 的释义作为高质量干扰项
  const confusedTerms = (content.confusedWords ?? []).map((item) => item.word).filter(Boolean);
  if (confusedTerms.length > 0) {
    const confusedRows = await findSpecificDistractorRows(confusedTerms, wordId);
    for (const row of confusedRows) {
      if (distractors.length >= 3) break;
      const text = preferredDefinitionText(row.definitions_json, targetLanguage);
      if (text && !seen.has(text.toLocaleLowerCase())) {
        seen.add(text.toLocaleLowerCase());
        distractors.push(text);
      }
    }
  }

  // 2. 其次融合用户自身的活跃错词本 (User's active wrong words)
  if (distractors.length < 3) {
    const wrongRows = await findActiveWrongDistractorRows(wordId);
    for (const row of wrongRows) {
      if (distractors.length >= 3) break;
      const text = preferredDefinitionText(row.definitions_json, targetLanguage);
      if (text && !seen.has(text.toLocaleLowerCase())) {
        seen.add(text.toLocaleLowerCase());
        distractors.push(text);
      }
    }
  }

  // 3. 最后从全局随机池中补齐
  if (distractors.length < 3) {
    const rows = await takeDistractorRows(new Set([wordId]), DISTRACTOR_TAKE_SIZE);
    for (const row of rows) {
      if (distractors.length >= 3) break;
      const text = preferredDefinitionText(row.definitions_json, targetLanguage);
      if (text && !seen.has(text.toLocaleLowerCase())) {
        seen.add(text.toLocaleLowerCase());
        distractors.push(text);
      }
    }
  }

  return shuffle([correct, ...distractors]);
}

async function generateWordChoices(wordId: number, term: string, targetLanguage: string, content: DictionaryContent): Promise<{ choices: string[]; choiceDefinitions: Record<string, string> }> {
  const correctDefinitions = targetDefinitionTexts(content.definitions, targetLanguage);
  if (!correctDefinitions) return { choices: [], choiceDefinitions: {} };
  const correct = term.trim();
  const choices = [correct];
  const choiceDefinitions: Record<string, string> = { [correct]: correctDefinitions };
  const seen = new Set([correct.toLocaleLowerCase()]);

  // 1. 优先提取易混词 (Confused words) 作为看汉选英的高质干扰项
  const confusedTerms = (content.confusedWords ?? []).map((item) => item.word).filter(Boolean);
  if (confusedTerms.length > 0) {
    const confusedRows = await findSpecificDistractorRows(confusedTerms, wordId);
    for (const row of confusedRows) {
      if (choices.length >= 4) break;
      const cTerm = row.term.trim();
      const cDef = targetDefinitionTexts(row.definitions_json, targetLanguage);
      if (!cTerm || !cDef || seen.has(cTerm.toLocaleLowerCase())) continue;
      seen.add(cTerm.toLocaleLowerCase());
      choices.push(cTerm);
      choiceDefinitions[cTerm] = cDef;
    }
  }

  // 2. 其次融合用户自身活跃错词
  if (choices.length < 4) {
    const wrongRows = await findActiveWrongDistractorRows(wordId);
    for (const row of wrongRows) {
      if (choices.length >= 4) break;
      const cTerm = row.term.trim();
      const cDef = targetDefinitionTexts(row.definitions_json, targetLanguage);
      if (!cTerm || !cDef || seen.has(cTerm.toLocaleLowerCase())) continue;
      seen.add(cTerm.toLocaleLowerCase());
      choices.push(cTerm);
      choiceDefinitions[cTerm] = cDef;
    }
  }

  // 3. 最后从全局池中补齐
  if (choices.length < 4) {
    const rows = await takeDistractorRows(new Set([wordId]), DISTRACTOR_TAKE_SIZE);
    for (const row of rows) {
      if (choices.length >= 4) break;
      const candidateTerm = row.term.trim();
      const candidateDefinitions = targetDefinitionTexts(row.definitions_json, targetLanguage);
      if (!candidateTerm || !candidateDefinitions || seen.has(candidateTerm.toLocaleLowerCase())) continue;
      seen.add(candidateTerm.toLocaleLowerCase());
      choices.push(candidateTerm);
      choiceDefinitions[candidateTerm] = candidateDefinitions;
    }
  }
  return { choices: shuffle(choices), choiceDefinitions };
}
function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\\]\\]/g, "\\$&");
}

function buildClozeExtra(term: string, content: DictionaryContent): { sentence: string; translation: string | null; blankedSentence: string } | null {
  const candidates = (content.examples ?? [])
    .map((ex) => ({ sentence: String(ex.sentence ?? "").trim(), translation: (ex.translation as string | null) ?? null }))
    .filter((ex) => ex.sentence);
  let chosen = candidates.find((ex) => new RegExp(`\\b${escapeRegExp(term)}\\b`, "i").test(ex.sentence)) ?? candidates[0] ?? null;
  if (!chosen) return null;
  const blankedSentence = chosen.sentence.replace(new RegExp(`\\b${escapeRegExp(term)}\\b`, "gi"), "____");
  return { sentence: chosen.sentence, translation: chosen.translation, blankedSentence: blankedSentence === chosen.sentence ? chosen.sentence.replace(term, "____") : blankedSentence };
}

function buildLetterTiles(term: string): Array<{ id: string; value: string }> {
  const original = [...term].map((value, index) => ({ id: `${index}-${value}`, value }));
  let shuffled = shuffle(original);
  const unchanged = shuffled.map((tile) => tile.value).join("").toLocaleLowerCase() === term.toLocaleLowerCase();
  if (unchanged && shuffled.length > 1) shuffled = [...shuffled.slice(1), shuffled[0]!];
  return shuffled;
}

