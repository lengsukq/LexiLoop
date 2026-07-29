import { z } from "zod";

export const AI_LEXICAL_PROMPT_VERSION = "lexical-v3";
export const AI_LEXICAL_SCHEMA_VERSION = 2;
const nullableText = (max: number) => z.string().trim().max(max).nullable();
export const relatedSchema = z.object({ word: z.string().trim().min(1).max(120), translation: nullableText(240), partOfSpeech: nullableText(50), difference: nullableText(500).optional() }).passthrough();
export const outputSchema = z.object({
  term: z.string().trim().min(1).max(300),
  summary: z.object({ shortDefinition: nullableText(500), translation: nullableText(300), cefrLevel: z.enum(["A1", "A2", "B1", "B2", "C1", "C2"]).nullable(), frequency: z.enum(["VERY_COMMON", "COMMON", "NORMAL", "RARE"]).nullable() }).passthrough(),
  senses: z.array(z.object({
    id: z.string().trim().min(1).max(40), partOfSpeech: nullableText(50), definition: z.string().trim().min(1).max(1000), translation: z.string().trim().min(1).max(500), register: z.enum(["FORMAL", "INFORMAL", "NEUTRAL", "SLANG"]).nullable(), usageNote: nullableText(800),
    examples: z.array(z.object({ sentence: z.string().trim().min(1).max(600), translation: nullableText(600), difficulty: z.enum(["EASY", "NORMAL", "ADVANCED"]) }).passthrough()).min(1).max(2),
    synonyms: z.array(relatedSchema).max(8), antonyms: z.array(relatedSchema).max(6), collocations: z.array(z.object({ phrase: z.string().trim().min(1).max(200), translation: nullableText(300), example: nullableText(600) }).passthrough()).max(8),
  }).passthrough()).min(1).max(4),
  morphology: z.object({
    lemma: nullableText(120), forms: z.array(z.object({ type: z.enum(["LEMMA", "PAST", "PAST_PARTICIPLE", "PRESENT_PARTICIPLE", "THIRD_PERSON", "PLURAL", "COMPARATIVE", "SUPERLATIVE", "OTHER"]), value: z.string().trim().min(1).max(120) }).passthrough()).max(12),
    roots: z.array(z.object({ root: z.string().trim().min(1).max(100), meaning: z.string().trim().min(1).max(300), origin: nullableText(200) }).passthrough()).max(5),
    affixes: z.array(z.object({ value: z.string().trim().min(1).max(80), type: z.enum(["PREFIX", "SUFFIX"]), meaning: z.string().trim().min(1).max(300) }).passthrough()).max(6),
    wordFamily: z.array(relatedSchema.extend({ relation: z.string().trim().min(1).max(100) }).passthrough()).max(12),
  }).passthrough(),
  phrases: z.array(z.object({ phrase: z.string().trim().min(1).max(240), translation: nullableText(300), example: nullableText(600), kind: z.enum(["COLLOCATION", "PHRASE", "IDIOM"]) }).passthrough()).max(10),
  confusedWords: z.array(relatedSchema).max(8),
  sentenceAnalysis: z.object({ grammarPattern: nullableText(300), grammarExplanation: nullableText(1500), grammarNotes: z.array(z.string().trim().min(1).max(800)).max(8), keyExpressions: z.array(z.object({ expression: z.string().trim().min(1).max(240), meaning: z.string().trim().min(1).max(500), note: nullableText(600) }).passthrough()).max(10), similarExamples: z.array(z.object({ sentence: z.string().trim().min(1).max(800), translation: z.string().trim().min(1).max(800), focus: nullableText(500) }).passthrough()).max(6), variations: z.array(z.object({ sentence: z.string().trim().min(1).max(800), translation: nullableText(800) }).passthrough()).max(6) }).passthrough(),
  learning: z.object({ pronunciationTip: nullableText(500), mnemonic: nullableText(800), commonMistakes: z.array(z.string().trim().min(1).max(500)).max(8) }).passthrough(),
  tags: z.array(z.string().trim().min(1).max(50)).max(12),
}).passthrough();
export type AiLexicalOutput = z.infer<typeof outputSchema>;
export type ModelResponse = { text: string; inputTokens: number | null; outputTokens: number | null; finishReason: string | null };

export const JSON_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["term", "summary", "senses", "morphology", "phrases", "confusedWords", "sentenceAnalysis", "learning", "tags"],
  properties: {
    term: { type: "string" },
    summary: {
      type: "object", additionalProperties: false,
      required: ["shortDefinition", "translation", "cefrLevel", "frequency"],
      properties: {
        shortDefinition: { type: ["string", "null"] },
        translation: { type: ["string", "null"] },
        cefrLevel: { type: ["string", "null"], enum: ["A1", "A2", "B1", "B2", "C1", "C2", null] },
        frequency: { type: ["string", "null"], enum: ["VERY_COMMON", "COMMON", "NORMAL", "RARE", null] },
      },
    },
    senses: {
      type: "array", minItems: 1, maxItems: 4,
      items: {
        type: "object", additionalProperties: false,
        required: ["id", "partOfSpeech", "definition", "translation", "register", "usageNote", "examples", "synonyms", "antonyms", "collocations"],
        properties: {
          id: { type: "string" }, partOfSpeech: { type: ["string", "null"] }, definition: { type: "string" }, translation: { type: "string" },
          register: { type: ["string", "null"], enum: ["FORMAL", "INFORMAL", "NEUTRAL", "SLANG", null] }, usageNote: { type: ["string", "null"] },
          examples: { type: "array", minItems: 1, maxItems: 2, items: { type: "object", additionalProperties: false, required: ["sentence", "translation", "difficulty"], properties: { sentence: { type: "string" }, translation: { type: ["string", "null"] }, difficulty: { type: "string", enum: ["EASY", "NORMAL", "ADVANCED"] } } } },
          synonyms: { type: "array", maxItems: 8, items: { $ref: "#/$defs/related" } },
          antonyms: { type: "array", maxItems: 6, items: { $ref: "#/$defs/related" } },
          collocations: { type: "array", maxItems: 8, items: { type: "object", additionalProperties: false, required: ["phrase", "translation", "example"], properties: { phrase: { type: "string" }, translation: { type: ["string", "null"] }, example: { type: ["string", "null"] } } } },
        },
      },
    },
    morphology: {
      type: "object", additionalProperties: false,
      required: ["lemma", "forms", "roots", "affixes", "wordFamily"],
      properties: {
        lemma: { type: ["string", "null"] },
        forms: { type: "array", maxItems: 12, items: { type: "object", additionalProperties: false, required: ["type", "value"], properties: { type: { type: "string", enum: ["LEMMA", "PAST", "PAST_PARTICIPLE", "PRESENT_PARTICIPLE", "THIRD_PERSON", "PLURAL", "COMPARATIVE", "SUPERLATIVE", "OTHER"] }, value: { type: "string" } } } },
        roots: { type: "array", maxItems: 5, items: { type: "object", additionalProperties: false, required: ["root", "meaning", "origin"], properties: { root: { type: "string" }, meaning: { type: "string" }, origin: { type: ["string", "null"] } } } },
        affixes: { type: "array", maxItems: 6, items: { type: "object", additionalProperties: false, required: ["value", "type", "meaning"], properties: { value: { type: "string" }, type: { type: "string", enum: ["PREFIX", "SUFFIX"] }, meaning: { type: "string" } } } },
        wordFamily: { type: "array", maxItems: 12, items: { type: "object", additionalProperties: false, required: ["word", "translation", "partOfSpeech", "difference", "relation"], properties: { word: { type: "string" }, translation: { type: ["string", "null"] }, partOfSpeech: { type: ["string", "null"] }, difference: { type: ["string", "null"] }, relation: { type: "string" } } } },
      },
    },
    phrases: { type: "array", maxItems: 10, items: { type: "object", additionalProperties: false, required: ["phrase", "translation", "example", "kind"], properties: { phrase: { type: "string" }, translation: { type: ["string", "null"] }, example: { type: ["string", "null"] }, kind: { type: "string", enum: ["COLLOCATION", "PHRASE", "IDIOM"] } } } },
    confusedWords: { type: "array", maxItems: 8, items: { $ref: "#/$defs/related" } },
    sentenceAnalysis: {
      type: "object", additionalProperties: false,
      required: ["grammarPattern", "grammarExplanation", "grammarNotes", "keyExpressions", "similarExamples", "variations"],
      properties: {
        grammarPattern: { type: ["string", "null"] },
        grammarExplanation: { type: ["string", "null"] },
        grammarNotes: { type: "array", maxItems: 8, items: { type: "string" } },
        keyExpressions: { type: "array", maxItems: 10, items: { type: "object", additionalProperties: false, required: ["expression", "meaning", "note"], properties: { expression: { type: "string" }, meaning: { type: "string" }, note: { type: ["string", "null"] } } } },
        similarExamples: { type: "array", maxItems: 6, items: { type: "object", additionalProperties: false, required: ["sentence", "translation", "focus"], properties: { sentence: { type: "string" }, translation: { type: "string" }, focus: { type: ["string", "null"] } } } },
        variations: { type: "array", maxItems: 6, items: { type: "object", additionalProperties: false, required: ["sentence", "translation"], properties: { sentence: { type: "string" }, translation: { type: ["string", "null"] } } } },
      },
    },
    learning: { type: "object", additionalProperties: false, required: ["pronunciationTip", "mnemonic", "commonMistakes"], properties: { pronunciationTip: { type: ["string", "null"] }, mnemonic: { type: ["string", "null"] }, commonMistakes: { type: "array", maxItems: 8, items: { type: "string" } } } },
    tags: { type: "array", maxItems: 12, items: { type: "string" } },
  },
  $defs: {
    related: { type: "object", additionalProperties: false, required: ["word", "translation", "partOfSpeech", "difference"], properties: { word: { type: "string" }, translation: { type: ["string", "null"] }, partOfSpeech: { type: ["string", "null"] }, difference: { type: ["string", "null"] } } },
  },
} as const;
