/** Return a new array with the items shuffled (Fisher-Yates). The input is not mutated. */
export function shuffle<T>(items: readonly T[]): T[] {
  const output = [...items];
  for (let index = output.length - 1; index > 0; index -= 1) {
    const randomIndex = Math.floor(Math.random() * (index + 1));
    [output[index], output[randomIndex]] = [output[randomIndex]!, output[index]!];
  }
  return output;
}
