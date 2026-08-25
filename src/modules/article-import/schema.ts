import { z } from "zod";

export const aiSelectionItemSchema = z.object({
  term: z.string().min(1).max(60),
  reason: z.string().min(1).max(40),
  difficulty: z.number().int().min(1).max(5),
  cefrLevel: z.enum(["A1", "A2", "B1", "B2", "C1", "C2"]).nullable().optional(),
  frequency: z.enum(["VERY_COMMON", "COMMON", "NORMAL", "RARE"]).nullable().optional(),
});

export const aiSelectionResponseSchema = z.object({
  selected: z.array(aiSelectionItemSchema).max(100),
});

export type AiSelectionItem = z.infer<typeof aiSelectionItemSchema>;
export type AiSelectionResponse = z.infer<typeof aiSelectionResponseSchema>;
