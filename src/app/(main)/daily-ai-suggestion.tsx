"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { AlertCircle, ArrowRight, Brain, CheckCircle2, Loader2, RefreshCw, Sparkles, Target } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, buttonClass } from "@/components/ui";

interface DailySuggestion {
  dateKey: string;
  sourceDateKey: string;
  qualityScore: number | null;
  metrics: {
    reviewCount: number;
    correctCount: number;
    accuracy: number | null;
    againCount: number;
    hardCount: number;
    skippedCount: number;
    sessionCount: number;
    averageDurationMs: number | null;
    studyMinutes: number;
    completionRate: number | null;
    questionAccuracy: Record<string, number | null>;
  };
  headline: string;
  summary: string;
  strengths: string[];
  risks: string[];
  actions: string[];
  recommendedItems: Array<{
    wordId: number;
    term: string;
    definition: string | null;
    reason: string;
    questionType: string;
    score: number;
  }>;
  generator: "AI" | "RULE_BASED";
  configured: boolean;
  providerId: string | null;
  model: string | null;
  generationWarning: string | null;
  generatedAt: string;
}

const QUESTION_LABELS: Record<string, string> = {
  EN_TO_ZH: "英译中",
  EN_TO_ZH_CHOICE: "释义选择",
  ZH_TO_EN_SPELLING: "中文拼写",
  LISTENING_SPELLING: "听力拼写",
};

export function DailyAiSuggestion() {
  const [data, setData] = useState<DailySuggestion | null>(null);
  const [busy, setBusy] = useState<"load" | "refresh" | "">("load");
  const [error, setError] = useState("");

  const load = useCallback(async (force = false) => {
    setBusy(force ? "refresh" : "load");
    setError("");
    try {
      setData(await apiFetch<DailySuggestion>("/api/suggestions/today", { method: force ? "POST" : "GET" }));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "生成今日建议失败");
    } finally {
      setBusy("");
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  if (!data && busy === "load") {
    return <Card className="animate-fade-up stagger-2"><CardContent className="flex min-h-40 items-center justify-center gap-3 text-sm text-[#8e8e93]"><Loader2 className="size-5 animate-spin text-[#5856d6]" />正在分析昨日学习质量…</CardContent></Card>;
  }

  if (!data && error) {
    return <Card><CardContent className="flex flex-col items-center gap-3 py-8 text-center"><AlertCircle className="size-7 text-[#ff3b30]" /><div><b className="text-sm">AI 建议生成失败</b><p className="mt-1 text-xs text-[#8e8e93]">{error}</p></div><Button variant="outline" size="sm" onClick={() => void load()}><RefreshCw className="size-4" />重试</Button></CardContent></Card>;
  }

  if (!data) return null;
  const scoreTone = data.qualityScore === null ? "slate" : data.qualityScore >= 80 ? "green" : data.qualityScore >= 60 ? "amber" : "red";

  return <Card className="animate-fade-up stagger-2 overflow-hidden">
    <CardHeader>
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle className="flex items-center gap-2"><Sparkles className="size-5 text-[#af52de]" />今日 AI 学习建议</CardTitle>
            <Badge tone={data.generator === "AI" ? "purple" : "slate"}>{data.generator === "AI" ? "AI 生成" : "智能规则"}</Badge>
            <Badge tone={scoreTone}>昨日质量 {data.qualityScore ?? "无记录"}</Badge>
          </div>
          <p className="mt-1 text-xs text-[#8e8e93]">基于 {data.sourceDateKey} 的学习数据和当前复习状态生成</p>
        </div>
        <Button variant="ghost" size="sm" onClick={() => void load(true)} disabled={Boolean(busy)}>{busy === "refresh" ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}重新分析</Button>
      </div>
    </CardHeader>

    <CardContent>
      <div className="grid grid-cols-1 gap-5 lg:grid-cols-[0.9fr_1.1fr]">
        <div className="rounded-[20px] bg-gradient-to-br from-[#5856d6]/10 via-[#af52de]/[0.07] to-[#007aff]/[0.06] p-4 sm:p-5">
          <div className="flex items-start gap-4">
            <div className="grid size-16 shrink-0 place-items-center rounded-full border-[6px] border-white/70 bg-white/80 shadow-[0_8px_24px_rgba(88,86,214,0.12)] dark:border-white/[0.08] dark:bg-white/[0.08]">
              <span className="text-xl font-bold text-[#5856d6]">{data.qualityScore ?? "—"}</span>
            </div>
            <div className="min-w-0"><h3 className="text-lg font-bold tracking-tight">{data.headline}</h3><p className="mt-2 text-sm leading-6 text-[#6e6e73] dark:text-[#98989d]">{data.summary}</p></div>
          </div>

          <div className="mt-4 grid grid-cols-4 gap-2 text-center">
            <Metric label="作答" value={data.metrics.reviewCount} />
            <Metric label="正确率" value={data.metrics.accuracy === null ? "—" : `${data.metrics.accuracy}%`} />
            <Metric label="跳过" value={data.metrics.skippedCount} />
            <Metric label="分钟" value={data.metrics.studyMinutes} />
          </div>

          <div className="mt-4 space-y-2">
            {data.actions.slice(0, 3).map((action, index) => <div key={`${action}-${index}`} className="flex items-start gap-2 rounded-[12px] bg-white/60 p-2.5 text-sm dark:bg-black/15"><CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[#34c759]" /><span>{action}</span></div>)}
          </div>

          {data.generator === "RULE_BASED" && !data.configured && <div className="mt-4 rounded-[12px] border border-[#ff9500]/15 bg-[#ff9500]/[0.06] p-3 text-xs leading-relaxed text-[#c93400] dark:text-[#ff9f0a]">当前未启用“每日学习建议”模型，已使用本地规则生成。可在<Link href="/settings" className="mx-1 font-semibold underline">设置 → AI 模型</Link>中启用。</div>}
          {data.generationWarning && data.configured && <p className="mt-3 text-xs text-[#ff9500]">AI 调用失败，本次已回退到本地建议：{data.generationWarning}</p>}
        </div>

        <div>
          <div className="mb-3 flex items-center justify-between gap-3"><div className="min-w-0"><h3 className="flex items-center gap-2 text-sm font-semibold"><Target className="size-4 text-[#ff3b30]" />AI 今日必做题</h3><p className="mt-1 text-xs text-[#8e8e93]">优先处理昨天答错、仍在错词队列或已经到期的词条。</p></div><Badge tone="red" className="shrink-0">{data.recommendedItems.length} 题</Badge></div>
          {data.recommendedItems.length ? <>
            <div className="grid max-h-[290px] gap-2 overflow-y-auto pr-1 sm:grid-cols-2">
              {data.recommendedItems.map((item, index) => <div key={item.wordId} className="rounded-[15px] border border-black/[0.05] bg-black/[0.02] p-3 dark:border-white/[0.07] dark:bg-white/[0.03]">
                <div className="flex items-center justify-between gap-2"><span className="flex min-w-0 items-center gap-2"><span className="grid size-6 shrink-0 place-items-center rounded-full bg-[#ff3b30]/10 text-[11px] font-bold text-[#ff3b30]">{index + 1}</span><b className="min-w-0 truncate text-sm">{item.term}</b></span><Badge tone="slate" className="shrink-0">{QUESTION_LABELS[item.questionType] ?? "复习"}</Badge></div>
                {item.definition && <p className="mt-2 truncate text-xs text-[#6e6e73] dark:text-[#98989d]">{item.definition}</p>}
                <p className="mt-1.5 text-xs leading-relaxed text-[#8e8e93]">{item.reason}</p>
              </div>)}
            </div>
            <Link href="/study?mode=AI_RECOMMENDED" className={`${buttonClass("primary", "lg")} mt-4 w-full`}><Brain className="size-5" />开始 AI 必做题<ArrowRight className="size-5" /></Link>
          </> : <div className="grid min-h-52 place-items-center rounded-[18px] border border-dashed border-black/[0.08] text-center dark:border-white/[0.1]"><div><Target className="mx-auto size-7 text-[#34c759]" /><b className="mt-2 block text-sm">暂时没有高风险词条</b><p className="mt-1 text-xs text-[#8e8e93]">可以继续完成常规今日学习。</p></div></div>}
        </div>
      </div>
    </CardContent>
  </Card>;
}

function Metric({ label, value }: { label: string; value: number | string }) {
  return <div className="rounded-[12px] bg-white/60 px-2 py-2.5 dark:bg-black/15"><b className="block text-base">{value}</b><span className="text-[11px] text-[#8e8e93]">{label}</span></div>;
}
