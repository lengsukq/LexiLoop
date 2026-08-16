import { ApiError } from "@/lib/api";
import type { QuestionType } from "@/lib/types";
import { selectPracticeCandidates } from "@/modules/practice/candidates";
import { createChoicePool, shuffle } from "@/modules/practice/random";
import {
  closeOpenPracticeSessions,
  createPracticeSession,
} from "@/modules/practice/sessions";
import type {
  PersistedStudyMode,
  PracticeAnswer,
  PracticeCandidate,
  PracticeCandidateRow,
  PracticeTaskType,
} from "@/modules/practice/types";
export { completeGameSession } from "./completion";

export const GAME_MODES = ["WORD_BUILDER", "LISTENING_PICK", "MEANING_BLITZ", "WHACK_A_MOLE", "WORD_STACK", "WORD_TETRIS"] as const;
export type GameMode = (typeof GAME_MODES)[number];

const MINIMUM_GAME_ITEMS = 4;
const CHOICE_COUNT = 4;

interface GameConfig {
  itemCount: number;
  durationSeconds: number;
  sessionType: PersistedStudyMode;
  questionType: QuestionType;
  taskType: PracticeTaskType;
}

const GAME_CONFIGS: Record<GameMode, GameConfig> = {
  WORD_BUILDER: {
    itemCount: 8,
    durationSeconds: 90,
    sessionType: "SPELLING",
    questionType: "ZH_TO_EN_SPELLING",
    taskType: "SPELLING",
  },
  LISTENING_PICK: {
    itemCount: 8,
    durationSeconds: 60,
    sessionType: "LISTENING",
    questionType: "LISTENING_SPELLING",
    taskType: "LISTENING",
  },
  MEANING_BLITZ: {
    itemCount: 10,
    durationSeconds: 45,
    sessionType: "DAILY",
    questionType: "EN_TO_ZH_CHOICE",
    taskType: "REVIEW",
  },
  WHACK_A_MOLE: {
    itemCount: 10,
    durationSeconds: 60,
    sessionType: "DAILY",
    questionType: "ZH_TO_EN_CHOICE",
    taskType: "REVIEW",
  },
  WORD_STACK: {
    itemCount: 8,
    durationSeconds: 75,
    sessionType: "DAILY",
    questionType: "ZH_TO_EN_CHOICE",
    taskType: "REVIEW",
  },
  WORD_TETRIS: {
    itemCount: 10,
    durationSeconds: 75,
    sessionType: "DAILY",
    questionType: "ZH_TO_EN_CHOICE",
    taskType: "REVIEW",
  },
};

export interface GameItem {
  itemId: number;
  wordId: number;
  term: string;
  definition: string;
  choices: string[];
  choiceDefinitions: Record<string, string>;
  letters: Array<{ id: string; value: string }>;
  priority: PracticeCandidate["priority"];
}

export interface GameSessionPayload {
  sessionId: number;
  mode: GameMode;
  durationSeconds: number;
  items: GameItem[];
}

export type GameAnswerInput = PracticeAnswer;

function isWordBuilderCandidate(candidate: PracticeCandidateRow): boolean {
  return candidate.content_type === "WORD" && /^[a-zA-Z]{3,14}$/.test(candidate.term);
}

function createLetterTiles(term: string): Array<{ id: string; value: string }> {
  const original = [...term].map((value, index) => ({ id: `${index}-${value}`, value }));
  let shuffled = shuffle(original);
  const unchanged = shuffled.map((tile) => tile.value).join("").toLocaleLowerCase() === term.toLocaleLowerCase();
  if (unchanged && shuffled.length > 1) shuffled = [...shuffled.slice(1), shuffled[0]!];
  return shuffled;
}

function createGameItems(
  mode: GameMode,
  candidates: readonly PracticeCandidate[],
  itemIds: ReadonlyMap<number, number>,
): GameItem[] {
  const terms = candidates.map((candidate) => candidate.term);
  const definitions = candidates.map((candidate) => candidate.definition);
  const termDefinitionMap = new Map(candidates.map((candidate) => [candidate.term, candidate.definition]));

  return candidates.map((candidate) => {
    const choices = mode === "MEANING_BLITZ"
      ? createChoicePool(candidate.definition, definitions, CHOICE_COUNT)
      : mode === "LISTENING_PICK" || mode === "WHACK_A_MOLE" || mode === "WORD_STACK" || mode === "WORD_TETRIS"
        ? createChoicePool(candidate.term, terms, CHOICE_COUNT)
        : [];
    return {
      itemId: itemIds.get(candidate.id)!,
      wordId: candidate.id,
      term: candidate.term,
      definition: candidate.definition,
      choices,
      choiceDefinitions: mode === "LISTENING_PICK"
        ? Object.fromEntries(choices.map((choice) => [choice, termDefinitionMap.get(choice) ?? ""]))
        : {},
      letters: mode === "WORD_BUILDER" ? createLetterTiles(candidate.term) : [],
      priority: candidate.priority,
    };
  });
}

export async function startGameSession(mode: GameMode): Promise<GameSessionPayload> {
  const now = Date.now();
  const config = GAME_CONFIGS[mode];
  await closeOpenPracticeSessions("GAME_%", now);

  const candidates = await selectPracticeCandidates({
    count: config.itemCount,
    now,
    candidateFilter: mode === "WORD_BUILDER" ? isWordBuilderCandidate : undefined,
  });
  if (candidates.length < MINIMUM_GAME_ITEMS) throw new ApiError("NOT_ENOUGH_GAME_WORDS");

  const sourceType = `GAME_${mode}`;
  const session = await createPracticeSession(candidates, {
    sourceType,
    sessionType: config.sessionType,
    questionType: config.questionType,
    defaultTaskType: config.taskType,
  }, now);
  const itemIds = new Map(session.items.map((item) => [item.wordId, item.itemId]));

  return {
    sessionId: session.sessionId,
    mode,
    durationSeconds: config.durationSeconds,
    items: createGameItems(mode, candidates, itemIds),
  };
}
