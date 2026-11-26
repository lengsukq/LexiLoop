import { shuffle } from "@/lib/array";

export { shuffle };

export function createChoicePool<T>(correct: T, values: readonly T[], size: number): T[] {
  const alternatives = shuffle(values.filter((value) => value !== correct)).slice(0, Math.max(0, size - 1));
  return shuffle([correct, ...alternatives]);
}
