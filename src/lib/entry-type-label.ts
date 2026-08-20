/** 词条类型 → 中文展示名，多处 UI 复用。 */
export function entryTypeLabel(entryType: string): string {
  return entryType === "WORD" ? "单词" : entryType === "SENTENCE" ? "句子" : "短语";
}
