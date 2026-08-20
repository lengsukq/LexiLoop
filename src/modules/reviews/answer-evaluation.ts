import type { ReviewRating } from "@/lib/types";
import { normalizeTerm } from "@/modules/imports/normalizer";
import { targetDefinitions, type DefinitionValue } from "@/modules/dictionary/content";
import type { AnswerInput, ReviewWordRow } from "./types";

export interface AnswerEvaluation {
  isCorrect: boolean;
  effectiveRating: ReviewRating;
  expectedAnswer: string;
  presentedPrompt: string;
}

function normalizeSentenceAnswer(value: string): string {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase()
    .replace(/[’‘]/g, "'")
    .replace(/[\p{P}\p{S}]+/gu, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function expectedAnswer(input: AnswerInput, word: ReviewWordRow, definitions: DefinitionValue[]): string {
  const definitionQuestion = input.questionType === "EN_TO_ZH" || input.questionType === "EN_TO_ZH_CHOICE";
  return definitionQuestion ? definitions.map((definition) => definition.text).join("；") : word.term;
}

function isAnswerCorrect(input: AnswerInput, word: ReviewWordRow, definitions: DefinitionValue[]): boolean {
  const spelling = input.questionType === "ZH_TO_EN_SPELLING" || input.questionType === "LISTENING_SPELLING";
  if (spelling) {
    if (word.content_type === "SENTENCE") {
      return normalizeSentenceAnswer(input.userAnswer ?? "") === normalizeSentenceAnswer(word.term);
    }
    return normalizeTerm(input.userAnswer ?? "", word.source_language) === word.normalized_term;
  }
  if (input.questionType === "EN_TO_ZH_CHOICE") {
    const correctDefinitions = definitions.map((definition) => definition.text.trim()).filter(Boolean);
    const answer = (input.userAnswer ?? "").trim();
    return correctDefinitions.length > 0
      ? [correctDefinitions.join("；"), ...correctDefinitions].some((correct) => answer === correct)
      : input.rating !== "AGAIN";
  }
  if (input.questionType === "ZH_TO_EN_CHOICE") {
    return normalizeTerm(input.userAnswer ?? "", word.source_language) === word.normalized_term;
  }
  return input.rating !== "AGAIN";
}

export function evaluateReviewAnswer(input: AnswerInput, word: ReviewWordRow): AnswerEvaluation {
  const definitions = targetDefinitions(word.definitions_json, word.target_language);
  const isCorrect = isAnswerCorrect(input, word, definitions);
  const objectivelyScored = input.questionType === "ZH_TO_EN_SPELLING"
    || input.questionType === "LISTENING_SPELLING"
    || input.questionType === "EN_TO_ZH_CHOICE"
    || input.questionType === "ZH_TO_EN_CHOICE";
  const respectsEasyChoice = objectivelyScored && !isCorrect && input.rating === "EASY";
  // A wrong answer rated "fuzzy" keeps the HARD grade: it is not treated as a
  // full lapse, so it enters the wrong-word pool but is reviewed in a later
  // session instead of being re-inserted into the current one.
  const respectsHardChoice = objectivelyScored && !isCorrect && input.rating === "HARD";
  const effectiveRating: ReviewRating = objectivelyScored && !isCorrect && !respectsEasyChoice && !respectsHardChoice ? "AGAIN" : input.rating;
  const expected = expectedAnswer(input, word, definitions);
  const definitionQuestion = input.questionType === "EN_TO_ZH" || input.questionType === "EN_TO_ZH_CHOICE";
  const reversePrompt = definitions.map((definition) => definition.text).join("；");

  return {
    isCorrect,
    effectiveRating,
    expectedAnswer: expected,
    presentedPrompt: definitionQuestion ? word.term : reversePrompt,
  };
}
