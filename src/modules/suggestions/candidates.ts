import { sqlite } from "@/db/client";
import type { QuestionType } from "@/lib/types";
import { DAY_MS } from "./date";
import { parseJson } from "@/lib/json";
import type {
  CandidateAccumulator,
  ReviewRow,
  SuggestionCandidate,
} from "./types";
const VALID_QUESTION_TYPES = new Set<QuestionType>([
  "EN_TO_ZH",
  "EN_TO_ZH_CHOICE",
  "ZH_TO_EN_SPELLING",
  "LISTENING_SPELLING",
]);
function accumulator(map: Map<number, CandidateAccumulator>, wordId: number): CandidateAccumulator {
  const existing = map.get(wordId);
  if (existing) return existing;
  const created: CandidateAccumulator = {
    wordId,
    attempts: 0,
    incorrect: 0,
    again: 0,
    hard: 0,
    durationTotal: 0,
    durationCount: 0,
    questionErrors: new Map(),
    wrongActive: false,
    wrongCount: 0,
    hardCount: 0,
    dueAt: null,
    difficulty: 0,
    lapses: 0,
    fallback: false,
  };
  map.set(wordId, created);
  return created;
}
function mostUsefulQuestion(candidate: CandidateAccumulator): QuestionType {
  const weakest = [...candidate.questionErrors.entries()]
    .sort((left, right) => right[1] - left[1])[0]?.[0];
  if (weakest && VALID_QUESTION_TYPES.has(weakest as QuestionType)) return weakest as QuestionType;
  if (candidate.wrongActive || candidate.incorrect > 0) return "ZH_TO_EN_SPELLING";
  return "EN_TO_ZH";
}
function reason(candidate: CandidateAccumulator, now: number): string {
  const parts: string[] = [];
  if (candidate.incorrect > 0) parts.push(`昨天答错 ${candidate.incorrect} 次`);
  if (candidate.again > 0) parts.push(`${candidate.again} 次选择忘记`);
  if (candidate.hard > 0) parts.push(`${candidate.hard} 次感觉模糊`);
  if (candidate.wrongActive && candidate.incorrect === 0) parts.push("仍在错词队列中");
  if (candidate.dueAt !== null && candidate.dueAt <= now) {
    const overdueDays = Math.max(0, Math.floor((now - candidate.dueAt) / DAY_MS));
    parts.push(overdueDays > 0 ? `已逾期 ${overdueDays} 天` : "今天到期");
  }
  if (!parts.length) parts.push("基础掌握度较低，建议优先巩固");
  return parts.slice(0, 2).join("，");
}
function score(candidate: CandidateAccumulator, now: number): number {
  const averageDuration = candidate.durationCount ? candidate.durationTotal / candidate.durationCount : 0;
  const overdueDays = candidate.dueAt !== null && candidate.dueAt <= now
    ? Math.max(0, (now - candidate.dueAt) / DAY_MS)
    : 0;
  return Math.round(
    candidate.incorrect * 120
    + candidate.again * 75
    + candidate.hard * 38
    + (candidate.wrongActive ? 55 : 0)
    + candidate.wrongCount * 7
    + candidate.hardCount * 4
    + Math.min(45, Math.max(0, averageDuration - 7_000) / 300)
    + (candidate.dueAt !== null && candidate.dueAt <= now ? 22 : 0)
    + Math.min(35, overdueDays * 4)
    + candidate.difficulty * 2
    + candidate.lapses * 5
    + (candidate.fallback ? 1 : 0),
  );
}
function preferredDefinition(raw: string | null, targetLanguage: string): string | null {
  const definitions = parseJson<Array<{ language?: string; text?: string }>>(raw, []);
  return definitions.find((item) => item.language === targetLanguage)?.text
    ?? definitions.find((item) => item.text)?.text
    ?? null;
}
function applyReviews(map: Map<number, CandidateAccumulator>, reviews: ReviewRow[]): void {
  for (const review of reviews) {
    const candidate = accumulator(map, review.word_id);
    candidate.attempts += 1;
    if (!review.is_correct) {
      candidate.incorrect += 1;
      candidate.questionErrors.set(
        review.question_type,
        (candidate.questionErrors.get(review.question_type) ?? 0) + 1,
      );
    }
    if (review.rating === "AGAIN") candidate.again += 1;
    if (review.rating === "HARD") candidate.hard += 1;
    if (review.duration_ms !== null) {
      candidate.durationTotal += review.duration_ms;
      candidate.durationCount += 1;
    }
  }
}
function applyWrongWords(map: Map<number, CandidateAccumulator>): void {
  const rows = sqlite.prepare(`SELECT word_id, wrong_count, hard_count FROM wrong_word_states
    WHERE active = 1 ORDER BY updated_at ASC LIMIT 200`).all() as Array<{
      word_id: number;
      wrong_count: number;
      hard_count: number;
    }>;
  for (const row of rows) {
    const candidate = accumulator(map, row.word_id);
    candidate.wrongActive = true;
    candidate.wrongCount = row.wrong_count;
    candidate.hardCount = row.hard_count;
  }
}
function applyDueCards(map: Map<number, CandidateAccumulator>, now: number): void {
  const rows = sqlite.prepare(`SELECT word_id, due_at, difficulty, lapses FROM review_cards
    WHERE due_at <= ? ORDER BY due_at ASC LIMIT 200`).all(now) as Array<{
      word_id: number;
      due_at: number;
      difficulty: number;
      lapses: number;
    }>;
  for (const row of rows) {
    const candidate = accumulator(map, row.word_id);
    candidate.dueAt = row.due_at;
    candidate.difficulty = row.difficulty;
    candidate.lapses = row.lapses;
  }
}
function riskCandidate(candidate: CandidateAccumulator, now: number): boolean {
  return candidate.incorrect > 0
    || candidate.again > 0
    || candidate.hard > 0
    || candidate.wrongActive
    || (candidate.dueAt !== null && candidate.dueAt <= now)
    || candidate.fallback;
}
function addFallbackCandidates(map: Map<number, CandidateAccumulator>): void {
  const rows = sqlite.prepare(`SELECT w.id FROM words w
    WHERE w.is_suspended = 0 AND w.initialization_status IN ('READY','PARTIAL')
    ORDER BY w.mastery_score ASC, COALESCE(w.source_created_at, w.created_at) ASC LIMIT 12`)
    .all() as Array<{ id: number }>;
  for (const row of rows) accumulator(map, row.id).fallback = true;
}
export function buildSuggestionCandidates(now: number, reviews: ReviewRow[]): SuggestionCandidate[] {
  const candidates = new Map<number, CandidateAccumulator>();
  applyReviews(candidates, reviews);
  applyWrongWords(candidates);
  applyDueCards(candidates, now);
  if (![...candidates.values()].some((candidate) => riskCandidate(candidate, now))) {
    addFallbackCandidates(candidates);
  }
  const ranked = [...candidates.values()]
    .filter((candidate) => riskCandidate(candidate, now))
    .sort((left, right) => score(right, now) - score(left, now))
    .slice(0, 30);
  if (!ranked.length) return [];
  const placeholders = ranked.map(() => "?").join(",");
  const rows = sqlite.prepare(`SELECT w.id, w.term, w.target_language, wc.definitions_json
    FROM words w LEFT JOIN word_contents wc ON wc.word_id = w.id
    WHERE w.id IN (${placeholders}) AND w.is_suspended = 0
      AND w.initialization_status IN ('READY','PARTIAL')`)
    .all(...ranked.map((candidate) => candidate.wordId)) as Array<{
      id: number;
      term: string;
      target_language: string;
      definitions_json: string | null;
    }>;
  const words = new Map(rows.map((row) => [row.id, row]));
  return ranked.flatMap((candidate) => {
    const word = words.get(candidate.wordId);
    if (!word) return [];
    return [{
      wordId: candidate.wordId,
      term: word.term,
      definition: preferredDefinition(word.definitions_json, word.target_language),
      reason: reason(candidate, now),
      questionType: mostUsefulQuestion(candidate),
      score: score(candidate, now),
      attempts: candidate.attempts,
      incorrect: candidate.incorrect,
      again: candidate.again,
      hard: candidate.hard,
      wrongActive: candidate.wrongActive,
      overdueDays: candidate.dueAt !== null && candidate.dueAt <= now
        ? Math.max(0, Math.floor((now - candidate.dueAt) / DAY_MS))
        : 0,
    } satisfies SuggestionCandidate];
  });
}
