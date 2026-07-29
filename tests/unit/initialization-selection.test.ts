import { describe, expect, it } from "vitest";
import { emptyDictionaryContent } from "@/modules/dictionary/content";
import { mergeRequestedFields, requestedFieldStatus } from "@/modules/dictionary/selection";

describe("field-level initialization merge", () => {
  it("refreshes only phonetics while preserving definitions, examples and existing audio", () => {
    const existing = emptyDictionaryContent();
    existing.definitions = [{ language: "zh-CN", partOfSpeech: "noun", text: "保证", source: "user", isUserEdited: true }];
    existing.examples = [{ sentence: "I guarantee it.", translation: "我保证。", source: "user", isUserAdded: true }];
    existing.pronunciations = [{ accent: "US", phonetic: "old", audioUrl: "https://audio.test/old.mp3", source: "dictionaryapi.dev", isSynthetic: false }];

    const incoming = emptyDictionaryContent();
    incoming.pronunciations = [{ accent: "US", phonetic: "ˌgerənˈtiː", audioUrl: null, source: "merriam-webster", isSynthetic: false }];

    const result = mergeRequestedFields(existing, incoming, ["pronunciations.phonetic"], "FORCE_OVERWRITE");
    expect(result.definitions).toEqual(existing.definitions);
    expect(result.examples).toEqual(existing.examples);
    expect(result.pronunciations).toEqual([
      { accent: "US", phonetic: "ˌgerənˈtiː", audioUrl: "https://audio.test/old.mp3", source: "dictionaryapi.dev", isSynthetic: false },
    ]);
  });

  it("keeps manual definitions when refreshing dictionary definitions", () => {
    const existing = emptyDictionaryContent();
    existing.definitions = [
      { language: "zh-CN", partOfSpeech: null, text: "我的手动释义", source: "user", isUserEdited: true },
      { language: "en", partOfSpeech: "noun", text: "old definition", source: "dictionaryapi.dev", isUserEdited: false },
    ];
    const incoming = emptyDictionaryContent();
    incoming.definitions = [{ language: "en", partOfSpeech: "noun", text: "new definition", source: "merriam-webster", isUserEdited: false }];

    const result = mergeRequestedFields(existing, incoming, ["definitions"], "FORCE_OVERWRITE");
    expect(result.definitions.map((item) => item.text)).toEqual(["我的手动释义", "new definition"]);
  });

  it("evaluates task success against only the requested fields", () => {
    const content = emptyDictionaryContent();
    content.pronunciations = [{ accent: "US", phonetic: "test", audioUrl: null, source: "ecdict", isSynthetic: false }];
    expect(requestedFieldStatus(content, ["pronunciations.phonetic"])).toBe("READY");
    expect(requestedFieldStatus(content, ["pronunciations.phonetic", "pronunciations.audio"])).toBe("PARTIAL");
    expect(requestedFieldStatus(content, ["definitions"])).toBe("FAILED");
  });
});
