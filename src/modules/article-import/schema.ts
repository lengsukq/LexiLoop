import { z } from "zod";

const keyVocabSchema = z.object({
  term: z.string().min(1).max(40),
  pos: z.string().min(1).max(20).nullable().optional(),
  meaning: z.string().min(1).max(80),
});
const grammarSchema = z.object({
  pattern: z.string().min(1).max(120).nullable().optional(),
  notes: z.array(z.string().min(1).max(200)).max(4).default([]),
}).partial();

export const aiSelectionItemSchema = z.object({
  term: z.string().min(1).max(60),
  reason: z.string().min(1).max(40),
  difficulty: z.number().int().min(1).max(5),
  cefrLevel: z.enum(["A1", "A2", "B1", "B2", "C1", "C2"]).nullable().optional(),
  frequency: z.enum(["VERY_COMMON", "COMMON", "NORMAL", "RARE"]).nullable().optional(),
});
export const aiPhraseItemSchema = z.object({
  term: z.string().min(1).max(60),
  reason: z.string().min(1).max(40),
  difficulty: z.number().int().min(1).max(5),
  cefrLevel: z.enum(["A1", "A2", "B1", "B2", "C1", "C2"]).nullable().optional(),
  literalTranslation: z.string().min(1).max(200),
  freeTranslation: z.string().min(1).max(200),
  keyVocab: z.array(keyVocabSchema).max(8).default([]),
  grammar: grammarSchema.optional(),
  nuance: z.string().min(1).max(120).nullable().optional(),
});
export const aiSentenceItemSchema = z.object({
  sentence: z.string().min(1).max(600),
  literalTranslation: z.string().min(1).max(400),
  freeTranslation: z.string().min(1).max(400),
  keyVocab: z.array(keyVocabSchema).max(10).default([]),
  grammar: grammarSchema.optional(),
  nuance: z.string().min(1).max(200).nullable().optional(),
});

export const aiSelectionResponseSchema = z.object({
  selected: z.array(aiSelectionItemSchema).max(100).optional(),
  words: z.array(aiSelectionItemSchema).max(100).optional(),
  phrases: z.array(aiPhraseItemSchema).max(20).optional(),
  sentences: z.array(aiSentenceItemSchema).max(20).optional(),
}).superRefine((val, ctx) => {
  const total = (val.words?.length ?? val.selected?.length ?? 0) + (val.phrases?.length ?? 0) + (val.sentences?.length ?? 0);
  if (total === 0) ctx.addIssue({ code: z.ZodIssueCode.custom, message: "empty selection", path: ["words"] });
});

export type AiSelectionItem = z.infer<typeof aiSelectionItemSchema>;
export type AiPhraseItem = z.infer<typeof aiPhraseItemSchema>;
export type AiSentenceItem = z.infer<typeof aiSentenceItemSchema>;
export type AiSelectionResponse = z.infer<typeof aiSelectionResponseSchema>;

export function normalizeLegacyResponse(parsed: unknown): z.infer<typeof aiSelectionResponseSchema> | null {
  const r = aiSelectionResponseSchema.safeParse(parsed);
  if (!r.success) return null;
  if (r.data.words || r.data.phrases || r.data.sentences) return r.data;
  if (r.data.selected?.length) return { words: r.data.selected, phrases: [], sentences: [] };
  return null;
}
