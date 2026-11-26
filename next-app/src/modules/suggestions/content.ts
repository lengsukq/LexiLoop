import type {
  AiSuggestionOutput,
  DailySuggestionMetrics,
  RecommendedStudyItem,
  SuggestionCandidate,
  SuggestionContent,
} from "./types";
import { SECOND_MS } from "@/lib/time";

export const RECOMMENDATION_LIMIT = 8;

const QUESTION_LABELS: Record<string, string> = {
  EN_TO_ZH: "英译中",
  EN_TO_ZH_CHOICE: "释义选择",
  ZH_TO_EN_SPELLING: "中文拼写",
  LISTENING_SPELLING: "听力拼写",
};

function weakestQuestion(metrics: DailySuggestionMetrics): string | null {
  const entry = Object.entries(metrics.questionAccuracy)
    .filter(([, accuracy]) => accuracy !== null)
    .sort((left, right) => (left[1] ?? 101) - (right[1] ?? 101))[0];
  if (!entry || entry[1] === null || entry[1] >= 75) return null;
  return `${QUESTION_LABELS[entry[0]] ?? entry[0]}正确率 ${entry[1]}%`;
}

function riskCounts(candidates: SuggestionCandidate[]) {
  return {
    highRisk: candidates.filter((candidate) => candidate.incorrect > 0 || candidate.again > 0 || candidate.wrongActive).length,
    overdue: candidates.filter((candidate) => candidate.overdueDays > 0).length,
  };
}

export function ruleBasedSuggestion(
  metrics: DailySuggestionMetrics,
  candidates: SuggestionCandidate[],
): SuggestionContent {
  const { highRisk, overdue } = riskCounts(candidates);

  if (!metrics.reviewCount) {
    const currentRisk = [
      highRisk ? `${highRisk} 个高风险词条` : "",
      overdue ? `${overdue} 个逾期词条` : "",
    ].filter(Boolean).join("，");
    return {
      headline: currentRisk ? "先清理高风险复习" : "今天先恢复学习节奏",
      summary: currentRisk
        ? `昨天没有答题记录，当前有${currentRisk}。今天先完成一小组重点复习，再决定是否增加新词。`
        : "昨天没有答题记录。今天先完成一小组复习，恢复学习节奏后再逐步增加学习量。",
      strengths: [],
      risks: currentRisk ? [`学习中断让${currentRisk}暂未处理`] : ["连续中断会让复习节奏变得不稳定"],
      actions: [
        candidates.length ? `先完成 ${Math.min(RECOMMENDATION_LIMIT, candidates.length)} 道重点复习` : "先完成一小组 5 道复习题",
        "完成复习后再决定是否增加新词",
        "今天保持一次完整学习会话，先把节奏找回来",
      ],
    };
  }

  const accuracy = metrics.accuracy ?? 0;
  const completion = metrics.completionRate ?? 0;
  const slow = metrics.averageDurationMs !== null && metrics.averageDurationMs > 15 * SECOND_MS;
  const weakQuestion = weakestQuestion(metrics);
  const lowAccuracy = accuracy < 75 || metrics.againCount > 0;
  const overloaded = metrics.skippedCount > Math.max(3, metrics.reviewCount * 0.25);
  const strengths = [
    ...(accuracy >= 80 ? [`昨天答对 ${metrics.correctCount} 题，正确率达到 ${accuracy}%`] : []),
    ...(completion >= 90 ? [`昨日学习完成度为 ${completion}%`] : []),
    ...(metrics.skippedCount === 0 && metrics.reviewCount >= 10 ? ["昨天完成了安排的复习，没有跳过题目"] : []),
    ...(metrics.studyMinutes >= 15 ? [`昨天保持了约 ${metrics.studyMinutes} 分钟的学习投入`] : []),
  ];
  const risks = [
    ...(accuracy < 75 ? [`昨天正确率为 ${accuracy}%，需要优先修复错误而不是追求数量`] : []),
    ...(metrics.againCount > 0 ? [`有 ${metrics.againCount} 题选择“忘记”，这些词需要尽快重复回忆`] : []),
    ...(metrics.hardCount > 0 ? [`有 ${metrics.hardCount} 题感觉模糊，容易在相近含义之间混淆`] : []),
    ...(metrics.skippedCount > 0 ? [`跳过了 ${metrics.skippedCount} 题，复习任务出现积压`] : []),
    ...(slow ? ["平均答题时间偏长，可能存在犹豫或反复查看提示"] : []),
    ...(highRisk > 0 ? [`当前仍有 ${highRisk} 个高风险词条需要优先处理`] : []),
    ...(weakQuestion ? [`${weakQuestion}，今天可以先练这一类题型`] : []),
  ].slice(0, 4);
  const actions: string[] = [];

  if (highRisk > 0) {
    actions.push(`先完成 ${Math.min(RECOMMENDATION_LIMIT, highRisk)} 道重点复习，优先处理答错或选择“忘记”的词`);
  } else if (overdue > 0) {
    actions.push(`先完成 ${Math.min(RECOMMENDATION_LIMIT, overdue)} 道逾期复习，避免继续积压`);
  } else {
    actions.push("先完成一小组常规复习，再开始新的学习内容");
  }
  if (lowAccuracy) {
    actions.push("今天暂缓增加新词，把时间集中在错词和拼写回忆");
  } else if (accuracy >= 90 && completion >= 90) {
    actions.push("保持当前学习量，完成重点复习后再增加少量新词");
  } else {
    actions.push("先完成重点复习，再继续常规学习，不要一次加入过多新词");
  }
  if (overloaded) {
    actions.push("把跳过的题拆成两小批完成，降低一次学习的负担");
  } else if (slow) {
    actions.push("每题先独立回忆几秒，再查看提示，减少反复犹豫");
  } else if (weakQuestion) {
    actions.push(`把${weakQuestion.split("正确率")[0]}作为今天的第一组练习`);
  } else {
    actions.push("复习时先说出答案和用法，再查看释义确认");
  }

  return {
    headline: accuracy < 60
      ? "先修复错误，再恢复数量"
      : overloaded
        ? "先清理跳过的复习"
        : accuracy >= 85 && completion >= 90
          ? "保持状态，做一次精准巩固"
          : "重点修复昨天的薄弱词",
    summary: `昨天完成 ${metrics.reviewCount} 次作答，答对 ${metrics.correctCount} 题，正确率 ${accuracy}%，学习约 ${metrics.studyMinutes} 分钟。${highRisk ? `当前有 ${highRisk} 个高风险词条，今天先处理它们。` : "今天先完成重点复习，再继续常规学习。"}`,
    strengths: strengths.length ? strengths : ["完成了昨天的学习记录"],
    risks: risks.length ? risks : ["暂未发现明显风险，继续保持当前节奏"],
    actions,
  };
}

export function orderRecommendedItems(
  candidates: SuggestionCandidate[],
  ai: AiSuggestionOutput | null,
): RecommendedStudyItem[] {
  const byId = new Map(candidates.map((candidate) => [candidate.wordId, candidate]));
  const selected: RecommendedStudyItem[] = [];
  const seen = new Set<number>();

  for (const item of ai?.recommended ?? []) {
    const candidate = byId.get(item.wordId);
    if (!candidate || seen.has(candidate.wordId)) continue;
    seen.add(candidate.wordId);
    selected.push({ ...candidate, reason: item.reason });
    if (selected.length >= RECOMMENDATION_LIMIT) return selected;
  }
  for (const candidate of candidates) {
    if (seen.has(candidate.wordId)) continue;
    seen.add(candidate.wordId);
    selected.push(candidate);
    if (selected.length >= RECOMMENDATION_LIMIT) break;
  }
  return selected;
}
