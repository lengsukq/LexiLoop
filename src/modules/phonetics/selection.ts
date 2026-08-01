import type { PronunciationItem } from "@/lib/types";
import { selectPracticeCandidates } from "@/modules/practice/candidates";
import { createChoicePool, shuffle } from "@/modules/practice/random";
import type { PracticeCandidate, PracticeCandidateRow } from "@/modules/practice/types";
import type { PhoneticAccent, PhoneticChallengeType, PhoneticGameItem } from "@/modules/phonetics/types";

const CANDIDATE_POOL_SIZE = 48;
const OPTION_COUNT = 4;

interface PhoneticCandidate extends PracticeCandidate {
  phonetic: string;
  phoneticAccent: "US" | "UK";
}

function parsePronunciations(value: string): PronunciationItem[] {
  try {
    const parsed = JSON.parse(value) as unknown;
    return Array.isArray(parsed) ? parsed.filter((item): item is PronunciationItem => (
      Boolean(item)
      && typeof item === "object"
      && typeof (item as PronunciationItem).accent === "string"
      && typeof (item as PronunciationItem).phonetic === "string"
    )).map((item) => ({
      ...item,
      // Legacy rows may still contain GENERAL; treat them as US without
      // exposing a third accent in the game or settings.
      accent: (item as unknown as { accent: string }).accent === "UK" ? "UK" as const : "US" as const,
    })) : [];
  } catch {
    return [];
  }
}

function displayPhonetic(value: string): string {
  const normalized = value.trim().replace(/\s+/g, " ");
  if (!normalized) return "";
  if ((normalized.startsWith("/") && normalized.endsWith("/"))
    || (normalized.startsWith("[") && normalized.endsWith("]"))) return normalized;
  return `/${normalized}/`;
}

function selectPronunciation(
  pronunciationsJson: string,
  accent: PhoneticAccent,
): { phonetic: string; accent: "US" | "UK" } | null {
  const pronunciations = parsePronunciations(pronunciationsJson)
    .filter((item) => Boolean(item.phonetic?.trim()));
  const selected = pronunciations.find((item) => item.accent === accent);
  if (!selected?.phonetic) return null;
  const phonetic = displayPhonetic(selected.phonetic);
  return phonetic ? { phonetic, accent: selected.accent } : null;
}

function hasPronunciation(candidate: PracticeCandidateRow): boolean {
  // Cheap pre-filter; the actual accent-aware pronunciation lookup happens once
  // in selectPhoneticCandidates to avoid parsing pronunciations_json twice.
  return candidate.content_type === "WORD"
    && /^[a-zA-Z][a-zA-Z '-]{1,30}$/.test(candidate.term);
}

function phoneticIdentity(value: string): string {
  return value.toLocaleLowerCase().replace(/[\s/\[\]]+/g, "").trim();
}

function phoneticUnits(value: string): string[] {
  return [...phoneticIdentity(value)];
}

function phoneticSimilarity(left: string, right: string): number {
  const leftUnits = phoneticUnits(left);
  const rightUnits = phoneticUnits(right);
  const rightSet = new Set(rightUnits);
  const shared = leftUnits.filter((unit) => rightSet.has(unit)).length;
  const lengthPenalty = Math.abs(leftUnits.length - rightUnits.length);
  const stressMatch = /[ˈˌ]/.test(left) === /[ˈˌ]/.test(right) ? 2 : 0;
  return shared * 5 + stressMatch - lengthPenalty * 2;
}

function similarPhoneticChoices(correct: string, values: readonly string[]): string[] {
  const distractors = values
    .filter((value) => phoneticIdentity(value) !== phoneticIdentity(correct))
    .sort((left, right) => phoneticSimilarity(correct, right) - phoneticSimilarity(correct, left));
  const nearPool = distractors.slice(0, Math.max(8, OPTION_COUNT * 2));
  return createChoicePool(correct, shuffle(nearPool), OPTION_COUNT);
}

function wordSimilarity(left: string, right: string): number {
  const a = left.toLocaleLowerCase();
  const b = right.toLocaleLowerCase();
  let sharedPrefix = 0;
  while (sharedPrefix < Math.min(a.length, b.length) && a[sharedPrefix] === b[sharedPrefix]) sharedPrefix += 1;
  return sharedPrefix * 4 - Math.abs(a.length - b.length);
}

function similarWordChoices(correct: string, values: readonly string[]): string[] {
  const distractors = values
    .filter((value) => value.toLocaleLowerCase() !== correct.toLocaleLowerCase())
    .sort((left, right) => wordSimilarity(correct, right) - wordSimilarity(correct, left));
  return createChoicePool(correct, shuffle(distractors.slice(0, 10)), OPTION_COUNT);
}

function challengeType(index: number): PhoneticChallengeType {
  return ["SOUND_TO_PHONETIC", "PHONETIC_TO_WORD", "WORD_TO_PHONETIC"][index % 3] as PhoneticChallengeType;
}

export function selectPhoneticCandidates(options: {
  count: number;
  accent: PhoneticAccent;
  now: number;
}): PhoneticCandidate[] {
  const candidates = selectPracticeCandidates({
    count: CANDIDATE_POOL_SIZE,
    now: options.now,
    candidateFilter: (candidate) => hasPronunciation(candidate),
  });
  const selected: PhoneticCandidate[] = [];
  const phonetics = new Set<string>();

  for (const candidate of candidates) {
    const pronunciation = selectPronunciation(candidate.pronunciations_json, options.accent);
    if (!pronunciation) continue;
    const identity = phoneticIdentity(pronunciation.phonetic);
    if (!identity || phonetics.has(identity)) continue;
    phonetics.add(identity);
    selected.push({
      ...candidate,
      phonetic: pronunciation.phonetic,
      phoneticAccent: pronunciation.accent,
    });
    if (selected.length >= options.count) break;
  }
  return selected;
}

export function createPhoneticItems(
  candidates: readonly PhoneticCandidate[],
  itemIds: ReadonlyMap<number, number>,
): PhoneticGameItem[] {
  const terms = candidates.map((candidate) => candidate.term);
  const phonetics = candidates.map((candidate) => candidate.phonetic);

  return candidates.map((candidate, index) => {
    const type = challengeType(index);
    return {
      itemId: itemIds.get(candidate.id)!,
      wordId: candidate.id,
      term: candidate.term,
      definition: candidate.definition,
      phonetic: candidate.phonetic,
      phoneticAccent: candidate.phoneticAccent,
      challengeType: type,
      choices: type === "PHONETIC_TO_WORD"
        ? similarWordChoices(candidate.term, terms)
        : similarPhoneticChoices(candidate.phonetic, phonetics),
      priority: candidate.priority,
    };
  });
}
