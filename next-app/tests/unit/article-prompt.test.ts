import { describe, expect, it } from "vitest";
import { buildArticleSelectionPrompt } from "@/modules/article-import/prompt";

function baseCandidates() {
  return [
    { term: "water", normalizedTerm: "water", occurrences: 5 },
    { term: "snow", normalizedTerm: "snow", occurrences: 10 },
  ];
}

describe("buildArticleSelectionPrompt", () => {
  it("自适应档默认按 CET-4 及以上划线，A1/A2 与高频基础词直接排除", () => {
    const { userPrompt } = buildArticleSelectionPrompt({
      articleText: "water snow",
      candidates: baseCandidates(),
      knownSample: [],
      totalKnown: 0,
    });
    expect(userPrompt).toContain("A1-A2 基础词一律视为已知");
    expect(userPrompt).toContain("无论出现多少次都不选");
    expect(userPrompt).not.toContain("根据用户的已知词情况自适应判断");
  });

  it("规则行强调出现次数不等于值得学，并要求准确标注便于过滤", () => {
    const { userPrompt } = buildArticleSelectionPrompt({
      articleText: "water snow",
      candidates: baseCandidates(),
      knownSample: [],
      totalKnown: 0,
    });
    expect(userPrompt).toContain("出现次数多不代表值得学");
    expect(userPrompt).toContain("拿不准是 A1/A2 基础词时宁可不选");
  });

  it("多档位时就高不就低，不再要求兼顾低档基础词", () => {
    const { userPrompt } = buildArticleSelectionPrompt({
      articleText: "water snow",
      candidates: baseCandidates(),
      knownSample: [],
      totalKnown: 0,
      examTargets: ["CET4", "TOEFL"],
    });
    expect(userPrompt).toContain("就高不就低");
    expect(userPrompt).not.toContain("兼顾低档基础词");
  });
});
