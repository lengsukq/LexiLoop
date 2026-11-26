import { describe, expect, it } from "vitest";
import { contentStatus, emptyDictionaryContent, normalizeDictionaryContent } from "@/modules/dictionary/content";
import { hasInitializationField } from "@/modules/dictionary/selection";

function sentenceContent() {
  const content = emptyDictionaryContent();
  content.definitions.push({
    language: "zh-CN",
    partOfSpeech: null,
    text: "我已经完成工作了。",
    source: "test",
    isUserEdited: false,
  });
  return content;
}

describe("sentence content status", () => {
  it("treats a directly translated sentence without analysis as ready", () => {
    const content = sentenceContent();
    content.summary.translation = "我已经完成工作了。";
    expect(contentStatus(content, "SENTENCE")).toBe("READY");
  });

  it("marks a translated and analyzed sentence ready", () => {
    const content = sentenceContent();
    content.sentenceAnalysis.grammarNotes.push("现在完成时表示已经完成的动作。");
    expect(contentStatus(content, "SENTENCE")).toBe("READY");
  });

  it("does not require an example sentence for sentence entries", () => {
    const content = sentenceContent();
    content.sentenceAnalysis.keyExpressions.push({
      expression: "have finished",
      meaning: "已经完成",
      note: null,
    });
    expect(content.examples).toHaveLength(0);
    expect(contentStatus(content, "SENTENCE")).toBe("READY");
  });

  it("keeps lexical status rules unchanged", () => {
    const content = sentenceContent();
    expect(contentStatus(content, "WORD")).toBe("PARTIAL");
    content.examples.push({ sentence: "I finished the work.", translation: "我完成了工作。", source: "test", isUserAdded: false });
    expect(contentStatus(content, "WORD")).toBe("READY");
  });

  it("normalizes the structured AI grammar module and bilingual examples", () => {
    const content = normalizeDictionaryContent({
      sentenceAnalysis: {
        grammarPattern: "S + have/has + past participle + O",
        grammarExplanation: "现在完成时强调动作已经完成，并与当前状态有关。",
        grammarNotes: ["助动词 have/has 后使用过去分词。"],
        keyExpressions: [],
        similarExamples: [
          { sentence: "She has completed the report.", translation: "她已经完成了报告。", focus: "has + 过去分词" },
          { sentence: "They have cleaned the room.", translation: "他们已经打扫了房间。", focus: "have + 过去分词" },
          { sentence: "He has booked the tickets.", translation: "他已经订好了票。", focus: "has + 过去分词" },
        ],
        variations: [],
      },
    });

    expect(content.sentenceAnalysis.similarExamples[0]?.translation).toBe("她已经完成了报告。");
    expect(hasInitializationField(content, "sentenceAnalysis")).toBe(true);
  });

  it("treats legacy sentence notes as missing the new structured grammar module", () => {
    const content = sentenceContent();
    content.sentenceAnalysis.grammarNotes.push("这是旧版语法说明。");
    expect(hasInitializationField(content, "sentenceAnalysis")).toBe(false);
  });
});
