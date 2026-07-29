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
    if (questionType === "EN_TO_ZH_CHOICE") item.choices = generateChoices(Number(row.word_id), String(row.target_language), content);
    return item;
  });
  const resumeIndex = items.findIndex((item) => item.status === "PENDING");
  return { resumed, resumeIndex: resumeIndex === -1 ? items.length : resumeIndex, session: { id: Number(session.id), sessionType: session.source_type === "AI_RECOMMENDED" || session.source_type === "SENTENCE_REVIEW" ? String(session.source_type) : String(session.session_type), startedAt: new Date(Number(session.started_at)).toISOString(), completedAt: session.completed_at ? new Date(Number(session.completed_at)).toISOString() : null, plannedCount: Number(session.planned_count), completedCount: Number(session.completed_count), correctCount: Number(session.correct_count), wrongCount: Number(session.wrong_count), skippedCount: Number(session.skipped_count ?? 0), durationMs: session.duration_ms === null ? null : Number(session.duration_ms) }, items };
}

function generateChoices(wordId: number, targetLanguage: string, content: DictionaryContent): string[] {
  const definitions = content.definitions.filter((item) => item.language === targetLanguage).map((item) => item.text); const correct = definitions[0] ?? content.definitions[0]?.text ?? ""; if (!correct) return [];
  const rows = sqlite.prepare(`SELECT c.definitions_json FROM word_contents c JOIN words w ON w.id = c.word_id WHERE c.word_id != ? AND w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL') AND c.definitions_json IS NOT NULL AND c.definitions_json != '[]' ORDER BY RANDOM() LIMIT 12`).all(wordId) as Array<{ definitions_json: string }>;
  const distractors: string[] = []; const seen = new Set([correct.toLocaleLowerCase()]);
  for (const row of rows) { if (distractors.length >= 3) break; try { const defs = JSON.parse(row.definitions_json) as Array<{ language: string; text: string }>; const pool = defs.filter((item) => item.language === targetLanguage); const text = (pool.length ? pool : defs)[0]?.text; if (text && !seen.has(text.toLocaleLowerCase())) { seen.add(text.toLocaleLowerCase()); distractors.push(text); } } catch { /* ignore malformed legacy content */ } }
  const choices = [correct, ...distractors]; for (let index = choices.length - 1; index > 0; index--) { const other = Math.floor(Math.random() * (index + 1)); [choices[index], choices[other]] = [choices[other]!, choices[index]!]; } return choices;
}
