import { sqlite } from "@/db/client";
import type { DictionaryContent, EntryType, QuestionType, StudyItemView } from "@/lib/types";
import { dictionaryContentFromRow, emptyDictionaryContent } from "@/modules/dictionary/content";

export function getStudySession(sessionId: number, resumed = false) {
  const session = sqlite.prepare("SELECT * FROM study_sessions WHERE id = ?").get(sessionId) as Record<string, unknown> | undefined;
  if (!session) throw new Error("STUDY_SESSION_NOT_FOUND");
  const rows = sqlite.prepare(`SELECT i.id AS item_id, i.position, i.task_type, i.question_type, i.status, i.skip_reason, w.id AS word_id, w.term, w.source_language, w.target_language, w.content_type, c.definitions_json, c.pronunciations_json, c.examples_json, c.phrases_json, c.forms_json, c.synonyms_json, c.antonyms_json, c.word_family_json, c.confused_words_json, c.roots_json, c.affixes_json, c.summary_json, c.learning_json, c.sentence_analysis_json, c.tags_json FROM study_session_items i JOIN words w ON w.id = i.word_id LEFT JOIN word_contents c ON c.word_id = w.id WHERE i.study_session_id = ? ORDER BY i.position ASC`).all(sessionId) as Array<Record<string, unknown>>;
  const items: Array<StudyItemView & { status: string; skipReason: string | null }> = rows.map((row) => {
    const questionType = row.question_type as QuestionType; const content = row.definitions_json === null ? emptyDictionaryContent() : dictionaryContentFromRow(row);
    const item = { itemId: Number(row.item_id), position: Number(row.position), taskType: row.task_type as StudyItemView["taskType"], questionType, status: String(row.status), skipReason: row.skip_reason === null ? null : String(row.skip_reason), word: { id: Number(row.word_id), term: String(row.term), sourceLanguage: String(row.source_language), targetLanguage: String(row.target_language), entryType: row.content_type as EntryType, content } } as StudyItemView & { status: string; skipReason: string | null };
    if (questionType === "EN_TO_ZH_CHOICE") item.choices = generateMeaningChoices(Number(row.word_id), String(row.target_language), content);
    if (questionType === "ZH_TO_EN_CHOICE") {
      const payload = generateWordChoices(Number(row.word_id), String(row.term), String(row.target_language), content);
      item.choices = payload.choices;
      item.choiceDefinitions = payload.choiceDefinitions;
    }
    return item;
  });
  const resumeIndex = items.findIndex((item) => item.status === "PENDING");
  return { resumed, resumeIndex: resumeIndex === -1 ? items.length : resumeIndex, session: { id: Number(session.id), sessionType: session.source_type === "AI_RECOMMENDED" || session.source_type === "SENTENCE_REVIEW" ? String(session.source_type) : String(session.session_type), startedAt: new Date(Number(session.started_at)).toISOString(), completedAt: session.completed_at ? new Date(Number(session.completed_at)).toISOString() : null, plannedCount: Number(session.planned_count), completedCount: Number(session.completed_count), correctCount: Number(session.correct_count), wrongCount: Number(session.wrong_count), skippedCount: Number(session.skipped_count ?? 0), durationMs: session.duration_ms === null ? null : Number(session.duration_ms) }, items };
}

function definitionTexts(raw: string, targetLanguage: string): string[] {
  try {
    const definitions = JSON.parse(raw) as Array<{ language?: string; text?: string }>;
    const target = definitions.filter((item) => item.language === targetLanguage).map((item) => item.text?.trim() ?? "").filter(Boolean);
    return target.length ? target : definitions.map((item) => item.text?.trim() ?? "").filter(Boolean);
  } catch {
    return [];
  }
}

function targetDefinitionTexts(content: DictionaryContent, targetLanguage: string): string[] {
  const targetDefinitions = content.definitions.filter((item) => item.language === targetLanguage).map((item) => item.text.trim()).filter(Boolean);
  return targetDefinitions.length ? targetDefinitions : content.definitions.map((item) => item.text.trim()).filter(Boolean);
}

function shuffle<T>(items: T[]): T[] {
  for (let index = items.length - 1; index > 0; index--) {
    const other = Math.floor(Math.random() * (index + 1));
    [items[index], items[other]] = [items[other]!, items[index]!];
  }
  return items;
}

function generateMeaningChoices(wordId: number, targetLanguage: string, content: DictionaryContent): string[] {
  const definitions = targetDefinitionTexts(content, targetLanguage);
  const correct = definitions.join("；"); if (!correct) return [];
  const rows = sqlite.prepare(`SELECT c.definitions_json FROM word_contents c JOIN words w ON w.id = c.word_id WHERE c.word_id != ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') AND c.definitions_json IS NOT NULL AND c.definitions_json != '[]' ORDER BY RANDOM() LIMIT 12`).all(wordId) as Array<{ definitions_json: string }>;
  const distractors: string[] = []; const seen = new Set([correct.toLocaleLowerCase()]);
  for (const row of rows) { if (distractors.length >= 3) break; const text = definitionTexts(row.definitions_json, targetLanguage)[0]; if (text && !seen.has(text.toLocaleLowerCase())) { seen.add(text.toLocaleLowerCase()); distractors.push(text); } }
  return shuffle([correct, ...distractors]);
}

function generateWordChoices(wordId: number, term: string, targetLanguage: string, content: DictionaryContent): { choices: string[]; choiceDefinitions: Record<string, string> } {
  const correctDefinitions = targetDefinitionTexts(content, targetLanguage);
  if (!correctDefinitions.length) return { choices: [], choiceDefinitions: {} };
  const correct = term.trim();
  const choices = [correct];
  const choiceDefinitions: Record<string, string> = { [correct]: correctDefinitions.join("；") };
  const seen = new Set([correct.toLocaleLowerCase()]);
  const rows = sqlite.prepare(`SELECT w.term, c.definitions_json FROM word_contents c JOIN words w ON w.id = c.word_id WHERE c.word_id != ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') AND c.definitions_json IS NOT NULL AND c.definitions_json != '[]' ORDER BY RANDOM() LIMIT 12`).all(wordId) as Array<{ term: string; definitions_json: string }>;
  for (const row of rows) {
    if (choices.length >= 4) break;
    const candidateTerm = row.term.trim();
    const candidateDefinitions = definitionTexts(row.definitions_json, targetLanguage);
    if (!candidateTerm || !candidateDefinitions.length || seen.has(candidateTerm.toLocaleLowerCase())) continue;
    seen.add(candidateTerm.toLocaleLowerCase());
    choices.push(candidateTerm);
    choiceDefinitions[candidateTerm] = candidateDefinitions.join("；");
  }
  return { choices: shuffle(choices), choiceDefinitions };
}
