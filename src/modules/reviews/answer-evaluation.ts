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

const CONTRACTION_MAP: Record<string, string> = {
  "i'm": "i am",
  "you're": "you are",
  "he's": "he is",
  "she's": "she is",
  "it's": "it is",
  "we're": "we are",
  "they're": "they are",
  "i've": "i have",
  "you've": "you have",
  "we've": "we have",
  "they've": "they have",
  "i'd": "i would",
  "you'd": "you would",
  "he'd": "he would",
  "she'd": "she would",
  "we'd": "we would",
  "they'd": "they would",
  "i'll": "i will",
  "you'll": "you will",
  "he'll": "he will",
  "she'll": "she will",
  "we'll": "we will",
  "they'll": "they will",
  "isn't": "is not",
  "aren't": "are not",
  "wasn't": "was not",
  "weren't": "were not",
  "haven't": "have not",
  "hasn't": "has not",
  "hadn't": "had not",
  "won't": "will not",
  "wouldn't": "would not",
  "don't": "do not",
  "doesn't": "does not",
  "didn't": "did not",
  "can't": "cannot",
  "couldn't": "could not",
  "shouldn't": "should not",
  "mightn't": "might not",
  "mustn't": "must not",
  "that's": "that is",
  "what's": "what is",
  "where's": "where is",
  "there's": "there is",
  "here's": "here is",
  "who's": "who is",
  "how's": "how is",
  "let's": "let us",
};

const US_UK_MAP: Record<string, string> = {
  colour: "color",
  flavour: "flavor",
  honour: "honor",
  humour: "humor",
  labour: "labor",
  neighbour: "neighbor",
  rumour: "rumor",
  centre: "center",
  theatre: "theater",
  metre: "meter",
  litre: "liter",
  fibre: "fiber",
  analyse: "analyze",
  paralyse: "paralyze",
  organise: "organize",
  recognise: "recognize",
  realise: "realize",
  apologise: "apologize",
  criticise: "criticize",
  defence: "defense",
  licence: "license",
  offence: "offense",
  practise: "practice",
  travelling: "traveling",
  cancelled: "canceled",
  fulfil: "fulfill",
};

export function levenshteinDistance(a: string, b: string): number {
  if (a === b) return 0;
  if (!a.length) return b.length;
  if (!b.length) return a.length;

  const row: number[] = [];
  for (let j = 0; j <= b.length; j++) row[j] = j;

  for (let i = 1; i <= a.length; i++) {
    let prev = i;
    for (let j = 1; j <= b.length; j++) {
      const val = a[i - 1] === b[j - 1] ? row[j - 1]! : Math.min(row[j - 1]!, row[j]!, prev) + 1;
      row[j - 1] = prev;
      prev = val;
    }
    row[b.length] = prev;
  }
  return row[b.length]!;
}

export function normalizeSentenceAnswer(value: string): string {
  const words = value
    .normalize("NFKC")
    .toLocaleLowerCase()
    .replace(/[’‘]/g, "'")
    .split(/\s+/);

  const expanded = words.map((rawWord) => {
    let w = rawWord.replace(/^[\p{P}\p{S}]+|[\p{P}\p{S}]+$/gu, "");
    if (CONTRACTION_MAP[w]) w = CONTRACTION_MAP[w]!;
    if (US_UK_MAP[w]) w = US_UK_MAP[w]!;
    return w;
  }).filter(Boolean);

  return expanded.join(" ").replace(/[\p{P}\p{S}]+/gu, " ").replace(/\s+/g, " ").trim();
}

function expectedAnswer(input: AnswerInput, word: ReviewWordRow, definitions: DefinitionValue[]): string {
  const definitionQuestion = input.questionType === "EN_TO_ZH" || input.questionType === "EN_TO_ZH_CHOICE";
  return definitionQuestion ? definitions.map((definition) => definition.text).join("；") : word.term;
}

export function canonicalTerm(term: string): string {
  return US_UK_MAP[term] ?? term;
}

export function isAnswerCorrect(input: AnswerInput, word: ReviewWordRow, definitions: DefinitionValue[]): boolean {
  const spelling = input.questionType === "ZH_TO_EN_SPELLING" || input.questionType === "LISTENING_SPELLING";
  if (spelling) {
    if (word.content_type === "SENTENCE") {
      const userNorm = normalizeSentenceAnswer(input.userAnswer ?? "");
      const expectedNorm = normalizeSentenceAnswer(word.term);
      if (userNorm === expectedNorm) return true;
      if (expectedNorm.length > 20) {
        const dist = levenshteinDistance(userNorm, expectedNorm);
        if (dist <= Math.max(1, Math.floor(expectedNorm.length * 0.08))) return true;
      }
      return false;
    }
    const userTerm = normalizeTerm(input.userAnswer ?? "", word.source_language);
    const targetTerm = word.normalized_term;
    if (userTerm === targetTerm) return true;
    if (canonicalTerm(userTerm) === canonicalTerm(targetTerm)) return true;
    // 单词单字母手误容错（长度 >= 7 且编辑距离 <= 1）
    if (targetTerm.length >= 7 && levenshteinDistance(userTerm, targetTerm) <= 1) {
      return true;
    }
    return false;
  }
  if (input.questionType === "EN_TO_ZH_CHOICE") {
    const correctDefinitions = definitions.map((definition) => definition.text.trim()).filter(Boolean);
    const answer = (input.userAnswer ?? "").trim();
    return correctDefinitions.length > 0
      ? [correctDefinitions.join("；"), ...correctDefinitions].some((correct) => answer === correct)
      : input.rating !== "AGAIN";
  }
  if (input.questionType === "ZH_TO_EN_CHOICE") {
    const userTerm = normalizeTerm(input.userAnswer ?? "", word.source_language);
    if (userTerm === word.normalized_term) return true;
    if (canonicalTerm(userTerm) === canonicalTerm(word.normalized_term)) return true;
    return false;
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
