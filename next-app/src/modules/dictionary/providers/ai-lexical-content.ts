import { z } from "zod";
import type { DictionaryContent, LookupInput, RelatedWordItem, WordFormItem } from "@/lib/types";
import { emptyDictionaryContent } from "../content";
import { relatedSchema, type AiLexicalOutput } from "./ai-lexical-schema";

const normalized = (value: string) => value.normalize("NFKC").trim().replace(/\s+/g, " ").toLocaleLowerCase();
const isChineseMnemonic = (value: string | null) => (value?.match(/[\u3400-\u9fff]/g)?.length ?? 0) >= 8;
function related(items: Array<z.infer<typeof relatedSchema>>, relation: string, source: string): RelatedWordItem[] { return items.map((item) => ({ word: item.word, translation: item.translation, partOfSpeech: item.partOfSpeech, difference: item.difference ?? null, relation, source })); }

export function toContent(output: AiLexicalOutput, input: LookupInput, source: string): DictionaryContent {
  const content = emptyDictionaryContent(); const self = normalized(input.term); content.summary = output.summary;
  for (const sense of output.senses) {
    const common = { partOfSpeech: sense.partOfSpeech, source, isUserEdited: false, senseId: sense.id, register: sense.register, usageNote: sense.usageNote };
    content.definitions.push({ ...common, language: input.sourceLanguage, text: sense.definition }, { ...common, language: input.targetLanguage, text: sense.translation });
    content.examples.push(...sense.examples.map((item) => ({ sentence: item.sentence, translation: item.translation, source, isUserAdded: false, senseId: sense.id, difficulty: item.difficulty })));
    content.synonyms.push(...related(sense.synonyms, "SYNONYM", source).filter((item) => normalized(item.word) !== self));
    content.antonyms.push(...related(sense.antonyms, "ANTONYM", source).filter((item) => normalized(item.word) !== self));
    content.phrases.push(...sense.collocations.map((item) => ({ phrase: item.phrase, translation: item.translation, example: item.example, kind: "COLLOCATION" as const, senseId: sense.id, source })));
  }
  if (output.morphology.lemma) content.forms.push({ type: "LEMMA", value: output.morphology.lemma, source });
  content.forms.push(...output.morphology.forms.map((item): WordFormItem => ({ ...item, source })));
  content.roots = output.morphology.roots.map((item) => ({ ...item, source })); content.affixes = output.morphology.affixes.map((item) => ({ ...item, source }));
  content.wordFamily = output.morphology.wordFamily.filter((item) => normalized(item.word) !== self).map((item) => ({ word: item.word, translation: item.translation, partOfSpeech: item.partOfSpeech, difference: item.difference ?? null, relation: item.relation, source }));
  content.phrases.push(...output.phrases.map((item) => ({ ...item, source }))); content.confusedWords = related(output.confusedWords, "CONFUSED_WITH", source).filter((item) => normalized(item.word) !== self);
  content.learning = { ...output.learning, mnemonic: isChineseMnemonic(output.learning.mnemonic) ? output.learning.mnemonic : null }; content.sentenceAnalysis = output.sentenceAnalysis; content.tags = output.tags;
  return content;
}

export function semanticIssues(output: AiLexicalOutput, input: LookupInput): string[] {
  const acceptedTerms = new Set([normalized(input.term), ...output.morphology.forms.map((form) => normalized(form.value)), ...(output.morphology.lemma ? [normalized(output.morphology.lemma)] : [])].filter(Boolean));
  const issues: string[] = [];
  for (const sense of output.senses) {
    if (input.entryType === "SENTENCE") continue;
    if (!sense.examples.some((example) => [...acceptedTerms].some((term) => normalized(example.sentence).includes(term)))) issues.push(`词义 ${sense.id} 的例句未包含目标词或其词形`);
  }
  if (input.entryType === "SENTENCE") {
    if (!output.sentenceAnalysis.grammarPattern || !output.sentenceAnalysis.grammarExplanation) issues.push("句子内容缺少结构化语法骨架或中文语法解释");
    if (output.sentenceAnalysis.grammarNotes.length === 0) issues.push("句子内容缺少语法要点");
    if (output.sentenceAnalysis.similarExamples.length < 3) issues.push("句子内容至少需要 3 个同语法双语例句");
  }
  return issues;
}

export function qualityScore(output: AiLexicalOutput, input: LookupInput): number {
  const examples = output.senses.flatMap((sense) => sense.examples); const definitions = output.senses.filter((sense) => sense.definition && sense.translation);
  const relatedCount = output.senses.reduce((sum, sense) => sum + sense.synonyms.length + sense.antonyms.length + sense.collocations.length, 0);
  const morphologyCount = output.morphology.forms.length + output.morphology.wordFamily.length + output.morphology.roots.length + output.morphology.affixes.length;
  const exampleCoverage = examples.filter((example) => normalized(example.sentence).includes(normalized(input.term)) || output.morphology.forms.some((form) => normalized(example.sentence).includes(normalized(form.value)))).length;
  let score = Math.min(30, definitions.length * 15) + (output.summary.translation ? 15 : 0) + Math.min(20, examples.length * 7) + Math.min(10, relatedCount * 2) + (input.entryType === "WORD" ? Math.min(10, morphologyCount * 2) : 10);
  score += input.entryType === "SENTENCE" ? Math.min(10, (output.sentenceAnalysis.grammarPattern ? 2 : 0) + (output.sentenceAnalysis.grammarExplanation ? 2 : 0) + output.sentenceAnalysis.grammarNotes.length + output.sentenceAnalysis.keyExpressions.length + output.sentenceAnalysis.similarExamples.length) : examples.length === 0 ? 0 : Math.round(exampleCoverage / examples.length * 10);
  score += output.learning.mnemonic || output.learning.commonMistakes.length ? 5 : 0; return Math.min(100, score);
}
