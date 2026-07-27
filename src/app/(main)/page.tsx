"use client";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { AlertCircle, ArrowRight, BookOpen, Brain, CheckCircle2, Headphones, Loader2, PenLine, RefreshCw, RotateCcw, Sparkles, Upload } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { Badge, Card, CardContent, CardHeader, CardTitle, EmptyState, Progress, buttonClass } from "@/components/ui";

interface Dashboard {
  totalWords: number;
  masteredWords: number;
  initializedWords: number;
  failedWords: number;
  todayReviews: number;
  todaySkipped: number;
  todayProcessed: number;
  todayGoalTotal: number;
  todayAccuracy: number | null;
  plan: {
    dueReviewCount: number; plannedDueReviewCount: number;
    wrongWordCount: number; plannedWrongWordCount: number;
    newWordCount: number; plannedNewWordCount: number;
    plannedTotal: number; estimatedMinutes: number;
  };
}

export default function HomePage() {
  const [data, setData] = useState<Dashboard | null>(null);
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    setError("");
    try { setData(await apiFetch<Dashboard>("/api/dashboard")); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "加载失败"); }
  }, []);
  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer); }, [load]);

  if (!data && !error) return <div className="grid min-h-[70vh] place-items-center"><Loader2 className="size-8 animate-spin text-indigo-500" /></div>;
  if (error) return <EmptyState icon={<AlertCircle className="size-10 text-rose-500" />} title="首页数据加载失败" description={error} action={<button className={buttonClass("outline")} onClick={() => void load()}><RefreshCw className="size-4" />重试</button>} />;
  if (!data) return null;

  if (data.totalWords === 0) {
    return <div className="mx-auto max-w-3xl py-12"><EmptyState icon={<div className="grid size-20 place-items-center rounded-3xl bg-indigo-100 text-indigo-600 dark:bg-indigo-950"><BookOpen className="size-10" /></div>} title="从 EasyDict 收藏开始" description="导入 EasyDict Favorites CSV。LexiLoop 只初始化你实际收藏的词条，不会导入整本词典。" action={<Link href="/import" className={buttonClass("primary", "lg")}><Upload className="size-5" />导入 CSV</Link>} /></div>;
  }

  const completedToday = data.todayProcessed;
  const planProgress = data.todayGoalTotal ? completedToday / data.todayGoalTotal * 100 : 100;
  return <div className="space-y-7">
    <section className="overflow-hidden rounded-3xl bg-gradient-to-br from-indigo-600 via-violet-600 to-fuchsia-600 p-6 text-white shadow-xl shadow-indigo-200/50 sm:p-8 dark:shadow-none">
      <div className="flex flex-col gap-6 sm:flex-row sm:items-center sm:justify-between">
        <div><Badge className="bg-white/15 text-white">今日学习</Badge><h1 className="mt-4 text-3xl font-bold">保持词汇循环，不让记忆掉队</h1><p className="mt-2 max-w-xl text-sm text-indigo-100">今天还剩 {data.plan.plannedTotal} 个任务，预计 {data.plan.estimatedMinutes} 分钟。队列已经对到期词和错词去重。</p></div>
        <Link href="/study?mode=DAILY" className="inline-flex h-14 shrink-0 items-center justify-center gap-2 rounded-2xl bg-white px-6 font-semibold text-indigo-700 shadow-lg transition hover:-translate-y-0.5"><Sparkles className="size-5" />开始今日学习<ArrowRight className="size-5" /></Link>
      </div>
      <div className="mt-7"><div className="mb-2 flex justify-between text-xs text-indigo-100"><span>今日完成度</span><span>{completedToday}/{data.todayGoalTotal}</span></div><Progress value={planProgress} className="bg-white/20 [&>div]:bg-white" /></div>
    </section>

    <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
      {[
        { label: "总词数", value: data.totalWords, detail: `${data.initializedWords} 个可学习`, icon: BookOpen, tone: "bg-sky-100 text-sky-600 dark:bg-sky-950" },
        { label: "已掌握", value: data.masteredWords, detail: `${Math.round(data.masteredWords / Math.max(1, data.totalWords) * 100)}% 掌握率`, icon: CheckCircle2, tone: "bg-emerald-100 text-emerald-600 dark:bg-emerald-950" },
        { label: "今日已处理", value: data.todayProcessed, detail: data.todayAccuracy === null ? `${data.todaySkipped} 个稍后再学` : `${data.todayAccuracy}% 正确率 · 跳过 ${data.todaySkipped}`, icon: Brain, tone: "bg-violet-100 text-violet-600 dark:bg-violet-950" },
        { label: "初始化异常", value: data.failedWords, detail: data.failedWords ? "建议前往处理" : "词条状态正常", icon: AlertCircle, tone: data.failedWords ? "bg-rose-100 text-rose-600 dark:bg-rose-950" : "bg-slate-100 text-slate-500 dark:bg-slate-800" },
      ].map((item) => <Card key={item.label}><CardContent className="flex items-center gap-4 pt-5"><div className={`grid size-12 place-items-center rounded-2xl ${item.tone}`}><item.icon className="size-6" /></div><div><p className="text-sm text-slate-500">{item.label}</p><p className="text-2xl font-bold">{item.value}</p><p className="text-xs text-slate-400">{item.detail}</p></div></CardContent></Card>)}
    </section>

    <section className="grid gap-5 lg:grid-cols-[1.25fr_.75fr]">
      <Card><CardHeader><CardTitle>今日队列</CardTitle></CardHeader><CardContent className="grid gap-3 sm:grid-cols-3">
        <QueueCard icon={<RotateCcw className="size-5" />} label="到期复习" count={data.plan.dueReviewCount} planned={data.plan.plannedDueReviewCount} href="/study?mode=DUE_REVIEW" tone="blue" />
        <QueueCard icon={<AlertCircle className="size-5" />} label="错词强化" count={data.plan.wrongWordCount} planned={data.plan.plannedWrongWordCount} href="/study?mode=WRONG_WORDS" tone="red" />
        <QueueCard icon={<Sparkles className="size-5" />} label="新词学习" count={data.plan.newWordCount} planned={data.plan.plannedNewWordCount} href="/study?mode=NEW_WORDS" tone="purple" />
      </CardContent></Card>
      <Card><CardHeader><CardTitle>专项练习</CardTitle></CardHeader><CardContent className="space-y-3"><Link href="/study?mode=LISTENING" className="flex items-center justify-between rounded-2xl border border-slate-200 p-4 transition hover:border-indigo-300 hover:bg-indigo-50 dark:border-slate-700 dark:hover:bg-indigo-950/30"><span className="flex items-center gap-3"><span className="grid size-10 place-items-center rounded-xl bg-sky-100 text-sky-600 dark:bg-sky-950"><Headphones className="size-5" /></span><span><b className="block text-sm">听力拼写</b><small className="text-slate-400">听发音后输入词条</small></span></span><ArrowRight className="size-4 text-slate-400" /></Link><Link href="/study?mode=SPELLING" className="flex items-center justify-between rounded-2xl border border-slate-200 p-4 transition hover:border-indigo-300 hover:bg-indigo-50 dark:border-slate-700 dark:hover:bg-indigo-950/30"><span className="flex items-center gap-3"><span className="grid size-10 place-items-center rounded-xl bg-amber-100 text-amber-600 dark:bg-amber-950"><PenLine className="size-5" /></span><span><b className="block text-sm">中文拼写</b><small className="text-slate-400">根据释义回忆英文</small></span></span><ArrowRight className="size-4 text-slate-400" /></Link></CardContent></Card>
    </section>
  </div>;
}

function QueueCard({ icon, label, count, planned, href, tone }: { icon: React.ReactNode; label: string; count: number; planned: number; href: string; tone: "blue" | "red" | "purple" }) {
  const styles = { blue: "bg-sky-50 text-sky-700 dark:bg-sky-950/40", red: "bg-rose-50 text-rose-700 dark:bg-rose-950/40", purple: "bg-violet-50 text-violet-700 dark:bg-violet-950/40" };
  return <Link href={href} className={`rounded-2xl p-4 transition hover:-translate-y-0.5 ${styles[tone]}`}><div className="flex items-center justify-between">{icon}<ArrowRight className="size-4 opacity-50" /></div><p className="mt-4 text-3xl font-bold">{planned}</p><p className="text-sm font-medium">{label}</p><p className="mt-1 text-xs opacity-70">共 {count} 个待处理</p></Link>;
}
