/** Return a new array with the items shuffled (Fisher-Yates). The input is not mutated. */
export function shuffle<T>(items: readonly T[]): T[] {
  const output = [...items];
  for (let index = output.length - 1; index > 0; index -= 1) {
    const randomIndex = Math.floor(Math.random() * (index + 1));
    [output[index], output[randomIndex]] = [output[randomIndex]!, output[index]!];
  }
  return output;
}

/** Return a new Set with the value toggled (removed if present, added otherwise). */
export function toggleSetValue<T>(current: ReadonlySet<T>, value: T): Set<T> {
  const next = new Set(current);
  if (next.has(value)) next.delete(value);
  else next.add(value);
  return next;
}
