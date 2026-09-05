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
  const lenient = normalizeLenientResponse(parsed);
  if (lenient) {
    // 宽容解析优先：截断超长字段、补默认值，而不是整批回退。
    const r = aiSelectionResponseSchema.safeParse(lenient);
    if (r.success) {
      if (r.data.words || r.data.phrases || r.data.sentences) return r.data;
      if (r.data.selected?.length) return { words: r.data.selected, phrases: [], sentences: [] };
    }
    return lenientTotal(lenient) > 0 ? lenient : null;
  }
  const r = aiSelectionResponseSchema.safeParse(parsed);
  if (!r.success) return null;
  if (r.data.words || r.data.phrases || r.data.sentences) return r.data;
  if (r.data.selected?.length) return { words: r.data.selected, phrases: [], sentences: [] };
  return null;
}

const CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"] as const;
const FREQUENCIES = ["VERY_COMMON", "COMMON", "NORMAL", "RARE"] as const;

/** OpenAI 结构化输出（json_schema / json_object 降级）用的 JSON Schema。
 * 兼容 strict 模式：properties 里的每个 key 都必须出现在 required 中，
 * 可选字段用 null 联合类型表示。 */
export const AI_SELECTION_JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["words", "phrases", "sentences"],
  properties: {
    words: {
      type: "array",
      maxItems: 100,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["term", "reason", "difficulty", "cefrLevel", "frequency"],
        properties: {
          term: { type: "string" },
          reason: { type: "string" },
          difficulty: { type: "integer", minimum: 1, maximum: 5 },
          cefrLevel: { type: ["string", "null"], enum: ["A1", "A2", "B1", "B2", "C1", "C2", null] },
          frequency: { type: ["string", "null"], enum: ["VERY_COMMON", "COMMON", "NORMAL", "RARE", null] },
        },
      },
    },
    phrases: {
      type: "array",
      maxItems: 15,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["term", "reason", "difficulty", "cefrLevel", "literalTranslation", "freeTranslation", "keyVocab", "grammar", "nuance"],
        properties: {
          term: { type: "string" },
          reason: { type: "string" },
          difficulty: { type: "integer", minimum: 1, maximum: 5 },
          cefrLevel: { type: ["string", "null"] },
          literalTranslation: { type: "string" },
          freeTranslation: { type: "string" },
          keyVocab: {
            type: "array",
            maxItems: 8,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["term", "pos", "meaning"],
              properties: {
                term: { type: "string" },
                pos: { type: ["string", "null"] },
                meaning: { type: "string" },
              },
            },
          },
          grammar: {
            type: ["object", "null"],
            additionalProperties: false,
            required: ["pattern", "notes"],
            properties: {
              pattern: { type: ["string", "null"] },
              notes: { type: "array", items: { type: "string" } },
            },
          },
          nuance: { type: ["string", "null"] },
        },
      },
    },
    sentences: {
      type: "array",
      maxItems: 10,
      items: {
        type: "object",
        additionalProperties: false,
        required: ["sentence", "literalTranslation", "freeTranslation", "keyVocab", "grammar", "nuance"],
        properties: {
          sentence: { type: "string" },
          literalTranslation: { type: "string" },
          freeTranslation: { type: "string" },
          keyVocab: {
            type: "array",
            maxItems: 10,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["term", "pos", "meaning"],
              properties: {
                term: { type: "string" },
                pos: { type: ["string", "null"] },
                meaning: { type: "string" },
              },
            },
          },
          grammar: {
            type: ["object", "null"],
            additionalProperties: false,
            required: ["pattern", "notes"],
            properties: {
              pattern: { type: ["string", "null"] },
              notes: { type: "array", items: { type: "string" } },
            },
          },
          nuance: { type: ["string", "null"] },
        },
      },
    },
  },
} as const;

function lenientText(value: unknown, max: number): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.length > max ? trimmed.slice(0, max) : trimmed;
}

function lenientDifficulty(value: unknown): number {
  const num = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(num)) return 3;
  return Math.max(1, Math.min(5, Math.round(num)));
}

function lenientEnum<T extends string>(value: unknown, allowed: readonly T[]): T | null {
  if (typeof value !== "string") return null;
  const upper = value.trim().toUpperCase();
  return (allowed as readonly string[]).includes(upper) ? (upper as T) : null;
}

function lenientKeyVocab(value: unknown, max: number): Array<{ term: string; pos: string | null; meaning: string }> {
  if (!Array.isArray(value)) return [];
  const out: Array<{ term: string; pos: string | null; meaning: string }> = [];
  for (const item of value) {
    if (!item || typeof item !== "object") continue;
    const record = item as Record<string, unknown>;
    const term = lenientText(record.term, 40);
    const meaning = lenientText(record.meaning, 80);
    if (!term || !meaning) continue;
    out.push({ term, pos: lenientText(record.pos, 20), meaning });
    if (out.length >= max) break;
  }
  return out;
}

function lenientGrammar(value: unknown): { pattern: string | null; notes: string[] } | undefined {
  if (!value || typeof value !== "object") return undefined;
  const record = value as Record<string, unknown>;
  const notes = Array.isArray(record.notes)
    ? record.notes.map((n) => lenientText(n, 200)).filter((n): n is string => n != null).slice(0, 4)
    : [];
  return { pattern: lenientText(record.pattern, 120), notes };
}

function lenientWord(item: unknown): z.infer<typeof aiSelectionItemSchema> | null {
  if (!item || typeof item !== "object") return null;
  const record = item as Record<string, unknown>;
  const term = lenientText(record.term, 60);
  if (!term) return null;
  return {
    term,
    reason: lenientText(record.reason, 40) ?? "值得学习",
    difficulty: lenientDifficulty(record.difficulty),
    cefrLevel: lenientEnum(record.cefrLevel, CEFR_LEVELS),
    frequency: lenientEnum(record.frequency, FREQUENCIES),
  };
}

function lenientPhrase(item: unknown): z.infer<typeof aiPhraseItemSchema> | null {
  if (!item || typeof item !== "object") return null;
  const record = item as Record<string, unknown>;
  const term = lenientText(record.term, 60);
  const literalTranslation = lenientText(record.literalTranslation, 200);
  const freeTranslation = lenientText(record.freeTranslation, 200);
  if (!term || !literalTranslation || !freeTranslation) return null;
  return {
    term,
    reason: lenientText(record.reason, 40) ?? "值得学习",
    difficulty: lenientDifficulty(record.difficulty),
    cefrLevel: lenientEnum(record.cefrLevel, CEFR_LEVELS),
    literalTranslation,
    freeTranslation,
    keyVocab: lenientKeyVocab(record.keyVocab, 8),
    grammar: lenientGrammar(record.grammar),
    nuance: lenientText(record.nuance, 120),
  };
}

function lenientSentence(item: unknown): z.infer<typeof aiSentenceItemSchema> | null {
  if (!item || typeof item !== "object") return null;
  const record = item as Record<string, unknown>;
  const sentence = lenientText(record.sentence, 600);
  const literalTranslation = lenientText(record.literalTranslation, 400);
  const freeTranslation = lenientText(record.freeTranslation, 400);
  if (!sentence || !literalTranslation || !freeTranslation) return null;
  return {
    sentence,
    literalTranslation,
    freeTranslation,
    keyVocab: lenientKeyVocab(record.keyVocab, 10),
    grammar: lenientGrammar(record.grammar),
    nuance: lenientText(record.nuance, 200),
  };
}

function pickKey(record: Record<string, unknown>, names: string[]): unknown {
  for (const name of names) {
    if (record[name] !== undefined) return record[name];
  }
  const lowered = new Map(Object.keys(record).map((k) => [k.toLowerCase(), k] as const));
  for (const name of names) {
    const actual = lowered.get(name.toLowerCase());
    if (actual != null && record[actual] !== undefined) return record[actual];
  }
  return undefined;
}

function lenientList<T>(value: unknown, map: (item: unknown) => T | null, max: number): T[] {
  if (!Array.isArray(value)) return [];
  const out: T[] = [];
  for (const item of value) {
    const mapped = map(item);
    if (mapped) out.push(mapped);
    if (out.length >= max) break;
  }
  return out;
}

function lenientTotal(response: z.infer<typeof aiSelectionResponseSchema>): number {
  return (response.words?.length ?? response.selected?.length ?? 0) + (response.phrases?.length ?? 0) + (response.sentences?.length ?? 0);
}

function normalizeLenientResponse(parsed: unknown): z.infer<typeof aiSelectionResponseSchema> | null {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null;
  const record = parsed as Record<string, unknown>;
  const words = lenientList(pickKey(record, ["words", "selected"]), lenientWord, 100);
  const phrases = lenientList(pickKey(record, ["phrases"]), lenientPhrase, 20);
  const sentences = lenientList(pickKey(record, ["sentences"]), lenientSentence, 20);
  const response: z.infer<typeof aiSelectionResponseSchema> = { words, phrases, sentences };
  return lenientTotal(response) > 0 ? response : null;
}
