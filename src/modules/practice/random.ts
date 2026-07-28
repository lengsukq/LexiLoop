export function shuffle<T>(items: readonly T[]): T[] {
  const output = [...items];
  for (let index = output.length - 1; index > 0; index -= 1) {
    const randomIndex = Math.floor(Math.random() * (index + 1));
    [output[index], output[randomIndex]] = [output[randomIndex]!, output[index]!];
  }
  return output;
}

export function createChoicePool<T>(correct: T, values: readonly T[], size: number): T[] {
  const alternatives = shuffle(values.filter((value) => value !== correct)).slice(0, Math.max(0, size - 1));
  return shuffle([correct, ...alternatives]);
}
