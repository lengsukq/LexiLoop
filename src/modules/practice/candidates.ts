import { sqlite } from "@/db/client";
import type {
  PracticeCandidate,
  PracticeCandidateRow,
  PracticePriority,
  PracticeSelectionOptions,
} from "@/modules/practice/types";

const RECENT_MISTAKE_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const ACTIVE_SESSION_WINDOW_MS = 24 * 60 * 60 * 1000;
const CANDIDATE_QUERY_LIMIT = 160;

export function extractPreferredDefinition(definitionsJson: string, targetLanguage: string): string | null {
  try {
    const definitions = JSON.parse(definitionsJson) as Array<{ language?: string; text?: string }>;
    const targetDefinitions = definitions
      .filter((definition) => definition.language === targetLanguage && definition.text?.trim())
      .map((definition) => definition.text!.trim());
    const fallbackDefinitions = definitions
      .filter((definition) => definition.text?.trim())
      .map((definition) => definition.text!.trim());
    const selectedDefinitions = targetDefinitions.length ? targetDefinitions : fallbackDefinitions;
    return selectedDefinitions.join("；") || null;
  } catch {
    return null;
  }
}

export function practicePriority(candidate: PracticeCandidateRow, now: number): PracticePriority {
  if (candidate.wrong_active) return "WRONG";
  if (candidate.recent_again > 0 || candidate.recent_hard > 0) return "RECENT_MISTAKE";
  if (candidate.due_at !== null && candidate.due_at <= now) return "DUE";
  return "NORMAL";
}

function activeSessionExclusion(enabled: boolean): string {
  if (!enabled) return "";
  return `AND NOT EXISTS (
    SELECT 1 FROM study_session_items active_item
    JOIN study_sessions active_session ON active_session.id = active_item.study_session_id
    WHERE active_item.word_id = w.id
      AND active_item.status = 'PENDING'
      AND active_session.completed_at IS NULL
      AND active_session.started_at >= ?
  )`;
}

function loadCandidateRows(options: PracticeSelectionOptions): PracticeCandidateRow[] {
  const { now, excludeWordsInActiveSessions = false } = options;
  const parameters: number[] = [
    now - RECENT_MISTAKE_WINDOW_MS,
    now - RECENT_MISTAKE_WINDOW_MS,
  ];
  if (excludeWordsInActiveSessions) parameters.push(now - ACTIVE_SESSION_WINDOW_MS);
  parameters.push(now, CANDIDATE_QUERY_LIMIT);

  return sqlite.prepare(`SELECT
      w.id, w.term, w.normalized_term, w.source_language, w.target_language, w.content_type,
      c.definitions_json, c.pronunciations_json,
      COALESCE(x.active, 0) AS wrong_active,
      COALESCE(x.wrong_count, 0) AS wrong_count,
      COALESCE(x.hard_count, 0) AS hard_count,
      rc.due_at,
      COALESCE(w.mastery_score, 0) AS mastery_score,
      COALESCE(recent.recent_again, 0) AS recent_again,
      COALESCE(recent.recent_hard, 0) AS recent_hard
    FROM words w
    JOIN word_contents c ON c.word_id = w.id
    LEFT JOIN wrong_word_states x ON x.word_id = w.id
    LEFT JOIN review_cards rc ON rc.word_id = w.id
    LEFT JOIN (
      SELECT word_id,
        SUM(CASE WHEN reviewed_at >= ? AND rating = 'AGAIN' THEN 1 ELSE 0 END) AS recent_again,
        SUM(CASE WHEN reviewed_at >= ? AND rating = 'HARD' THEN 1 ELSE 0 END) AS recent_hard
      FROM review_logs
      GROUP BY word_id
    ) recent ON recent.word_id = w.id
    WHERE w.is_suspended = 0
      AND w.initialization_status IN ('READY', 'PARTIAL')
      ${activeSessionExclusion(excludeWordsInActiveSessions)}
    ORDER BY
      COALESCE(x.active, 0) DESC,
      COALESCE(recent.recent_again, 0) DESC,
      COALESCE(recent.recent_hard, 0) DESC,
      CASE WHEN rc.due_at IS NOT NULL AND rc.due_at <= ? THEN 1 ELSE 0 END DESC,
      COALESCE(x.wrong_count, 0) DESC,
      COALESCE(x.hard_count, 0) DESC,
      COALESCE(w.mastery_score, 0) ASC,
      RANDOM()
    LIMIT ?`).all(...parameters) as PracticeCandidateRow[];
}

function normalizedIdentity(value: string): string {
  return value.toLocaleLowerCase().replace(/\s+/g, " ").trim();
}

export function selectPracticeCandidates(options: PracticeSelectionOptions): PracticeCandidate[] {
  const selected: PracticeCandidate[] = [];
  const seenTerms = new Set<string>();
  const seenDefinitions = new Set<string>();

  for (const candidate of loadCandidateRows(options)) {
    if (options.candidateFilter && !options.candidateFilter(candidate)) continue;
    const definition = extractPreferredDefinition(candidate.definitions_json, candidate.target_language);
    if (!definition) continue;

    const termIdentity = normalizedIdentity(candidate.term);
    const definitionIdentity = normalizedIdentity(definition);
    if (seenTerms.has(termIdentity) || seenDefinitions.has(definitionIdentity)) continue;

    seenTerms.add(termIdentity);
    seenDefinitions.add(definitionIdentity);
    selected.push({
      ...candidate,
      definition,
      priority: practicePriority(candidate, options.now),
    });
    if (selected.length >= options.count) break;
  }

  return selected;
}
