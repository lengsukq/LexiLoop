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
    try {
      setData(await apiFetch<Dashboard>("/api/dashboard"));
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "加载失败");
    }
  }, []);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  if (!data && !error) {
    return (
      <div className="grid min-h-[70vh] place-items-center">
        <div className="animate-scale-in text-center">
          <Loader2 className="mx-auto size-10 animate-spin text-[#007aff]" />
          <p className="mt-3 text-[15px] text-[#8e8e93]">正在加载…</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <EmptyState
        icon={<AlertCircle className="size-10 text-[#ff3b30]" />}
        title="首页数据加载失败"
        description={error}
        action={<button className={buttonClass("outline")} onClick={() => void load()}><RefreshCw className="size-4" />重试</button>}
      />
    );
  }

  if (!data) return null;

  if (data.totalWords === 0) {
    return (
      <div className="mx-auto max-w-3xl py-12">
        <EmptyState
          icon={
            <div className="grid size-20 place-items-center rounded-[24px] bg-gradient-to-br from-[#007aff] to-[#5856d6] text-white shadow-[0_8px_24px_rgba(0,122,255,0.3)]">
              <BookOpen className="size-10" />
            </div>
          }
          title="从 EasyDict 收藏开始"
          description="导入 EasyDict Favorites CSV。LexiLoop 只初始化你实际收藏的词条，不会导入整本词典。"
          action={<Link href="/import" className={buttonClass("primary", "lg")}><Upload className="size-5" />导入 CSV</Link>}
        />
      </div>
    );
  }

  const completedToday = data.todayProcessed;
  const planProgress = data.todayGoalTotal ? (completedToday / data.todayGoalTotal) * 100 : 100;

  return (
    <div className="space-y-6">
      {/* Hero Card */}
      <section className="animate-fade-up relative overflow-hidden rounded-[28px] bg-gradient-to-br from-[#0a84ff] via-[#5856d6] to-[#af52de] p-8 text-white shadow-[0_16px_56px_rgba(0,122,255,0.3),0_4px_16px_rgba(0,0,0,0.1),inset_0_2px_0_rgba(255,255,255,0.2)] sm:p-10">
        <div className="absolute -right-20 -top-20 size-56 rounded-full bg-white/[0.08] blur-3xl" />
        <div className="absolute -bottom-16 -left-16 size-44 rounded-full bg-white/[0.06] blur-2xl" />
        <div className="absolute right-1/4 top-0 size-32 rounded-full bg-white/[0.04] blur-xl" />
        <div className="relative flex flex-col gap-7 sm:flex-row sm:items-center sm:justify-between">
          <div>
            <Badge className="bg-white/[0.18] text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.2)] backdrop-blur-md">今日学习</Badge>
            <h1 className="mt-5 text-[28px] font-bold leading-tight tracking-tight sm:text-[32px]">
              保持词汇循环，不让记忆掉队
            </h1>
            <p className="mt-3 max-w-xl text-[15px] leading-relaxed text-white/70">
              今天还剩 {data.plan.plannedTotal} 个任务，预计 {data.plan.estimatedMinutes} 分钟。
            </p>
          </div>
          <Link
            href="/study?mode=DAILY"
            className="ios-press inline-flex h-[54px] shrink-0 items-center justify-center gap-2.5 rounded-2xl bg-white/95 px-8 text-[17px] font-bold text-[#007aff] shadow-[0_6px_24px_rgba(0,0,0,0.15),inset_0_1px_0_rgba(255,255,255,1)] backdrop-blur-sm"
          >
            <Sparkles className="size-5" />
            开始学习
            <ArrowRight className="size-5" />
          </Link>
        </div>
        <div className="relative mt-8">
          <div className="mb-2.5 flex justify-between text-xs font-medium text-white/60">
            <span>今日完成度</span>
            <span>{completedToday}/{data.todayGoalTotal}</span>
          </div>
          <div className="h-[7px] overflow-hidden rounded-full bg-white/[0.15] shadow-[inset_0_1px_3px_rgba(0,0,0,0.1)]">
            <div
              className="h-full rounded-full bg-gradient-to-r from-white/90 to-white shadow-[0_1px_4px_rgba(255,255,255,0.4)] transition-all duration-700 ease-out"
              style={{ width: `${Math.min(100, planProgress)}%` }}
            />
          </div>
        </div>
      </section>

      {/* Stats Grid */}
      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {[
          { label: "总词数", value: data.totalWords, detail: `${data.initializedWords} 个可学习`, icon: BookOpen, gradient: "from-[#007aff] to-[#5ac8fa]" },
          { label: "已掌握", value: data.masteredWords, detail: `${Math.round((data.masteredWords / Math.max(1, data.totalWords)) * 100)}% 掌握率`, icon: CheckCircle2, gradient: "from-[#34c759] to-[#30d158]" },
          { label: "今日已处理", value: data.todayProcessed, detail: data.todayAccuracy === null ? `${data.todaySkipped} 个稍后再学` : `${data.todayAccuracy}% 正确率`, icon: Brain, gradient: "from-[#af52de] to-[#bf5af2]" },
          { label: "初始化异常", value: data.failedWords, detail: data.failedWords ? "建议前往处理" : "状态正常", icon: AlertCircle, gradient: data.failedWords ? "from-[#ff3b30] to-[#ff6961]" : "from-[#8e8e93] to-[#aeaeb2]" },
        ].map((item, index) => (
          <Card key={item.label} className={`ios-lift animate-fade-up stagger-${index + 1}`}>
            <CardContent className="flex items-center gap-4 pt-5">
              <div className={`grid size-12 place-items-center rounded-[14px] bg-gradient-to-br ${item.gradient} text-white shadow-lg`}>
                <item.icon className="size-6" />
              </div>
              <div>
                <p className="text-[13px] font-medium text-[#8e8e93] dark:text-[#636366]">{item.label}</p>
                <p className="text-[26px] font-bold tracking-tight">{item.value}</p>
                <p className="text-xs text-[#aeaeb2] dark:text-[#48484a]">{item.detail}</p>
              </div>
            </CardContent>
          </Card>
        ))}
      </section>

      {/* Queue + Practice */}
      <section className="grid gap-5 lg:grid-cols-[1.2fr_0.8fr]">
        <Card className="animate-fade-up stagger-3">
          <CardHeader><CardTitle>今日队列</CardTitle></CardHeader>
          <CardContent className="grid gap-3 sm:grid-cols-3">
            <QueueCard icon={<RotateCcw className="size-5" />} label="到期复习" count={data.plan.dueReviewCount} planned={data.plan.plannedDueReviewCount} href="/study?mode=DUE_REVIEW" gradient="from-[#007aff] to-[#5ac8fa]" />
            <QueueCard icon={<AlertCircle className="size-5" />} label="错词强化" count={data.plan.wrongWordCount} planned={data.plan.plannedWrongWordCount} href="/study?mode=WRONG_WORDS" gradient="from-[#ff3b30] to-[#ff6961]" />
            <QueueCard icon={<Sparkles className="size-5" />} label="新词学习" count={data.plan.newWordCount} planned={data.plan.plannedNewWordCount} href="/study?mode=NEW_WORDS" gradient="from-[#af52de] to-[#bf5af2]" />
          </CardContent>
        </Card>

        <Card className="animate-fade-up stagger-4">
          <CardHeader><CardTitle>专项练习</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <PracticeLink
              href="/study?mode=LISTENING"
              icon={<Headphones className="size-5" />}
              title="听力拼写"
              subtitle="听发音后输入词条"
              gradient="from-[#5ac8fa] to-[#007aff]"
            />
            <PracticeLink
              href="/study?mode=SPELLING"
              icon={<PenLine className="size-5" />}
              title="中文拼写"
              subtitle="根据释义回忆英文"
              gradient="from-[#ff9500] to-[#ff6961]"
            />
          </CardContent>
        </Card>
      </section>
    </div>
  );
}

function QueueCard({ icon, label, count, planned, href, gradient }: {
  icon: React.ReactNode; label: string; count: number; planned: number; href: string; gradient: string;
}) {
  return (
    <Link href={href} className="ios-press group glass-inner rounded-[20px] p-5 transition-all duration-300 hover:shadow-[0_12px_40px_rgba(0,0,0,0.08),0_4px_12px_rgba(0,0,0,0.04),inset_0_1px_0_rgba(255,255,255,0.9)] dark:hover:shadow-[0_12px_40px_rgba(0,0,0,0.3)]">
      <div className="flex items-center justify-between">
        <span className={`grid size-10 place-items-center rounded-[14px] bg-gradient-to-br ${gradient} text-white shadow-[0_4px_12px_rgba(0,0,0,0.15),inset_0_1px_0_rgba(255,255,255,0.3)]`}>{icon}</span>
        <ArrowRight className="size-4 text-[#c7c7cc] transition-transform duration-300 group-hover:translate-x-1 dark:text-[#38383a]" />
      </div>
      <p className="mt-5 text-[30px] font-bold tracking-tight">{planned}</p>
      <p className="text-[13px] font-semibold text-[#6e6e73] dark:text-[#98989d]">{label}</p>
      <p className="mt-1 text-xs text-[#aeaeb2] dark:text-[#48484a]">共 {count} 个待处理</p>
    </Link>
  );
}

function PracticeLink({ href, icon, title, subtitle, gradient }: {
  href: string; icon: React.ReactNode; title: string; subtitle: string; gradient: string;
}) {
  return (
    <Link href={href} className="ios-press group glass-inner flex items-center justify-between rounded-[20px] p-5 transition-all duration-300 hover:shadow-[0_12px_40px_rgba(0,0,0,0.08),0_4px_12px_rgba(0,0,0,0.04),inset_0_1px_0_rgba(255,255,255,0.9)] dark:hover:shadow-[0_12px_40px_rgba(0,0,0,0.3)]">
      <span className="flex items-center gap-3.5">
        <span className={`grid size-11 place-items-center rounded-[14px] bg-gradient-to-br ${gradient} text-white shadow-[0_4px_12px_rgba(0,0,0,0.15),inset_0_1px_0_rgba(255,255,255,0.3)]`}>{icon}</span>
        <span>
          <b className="block text-[15px] font-semibold">{title}</b>
          <small className="text-[13px] text-[#8e8e93] dark:text-[#636366]">{subtitle}</small>
        </span>
      </span>
      <ArrowRight className="size-4 text-[#c7c7cc] transition-transform duration-300 group-hover:translate-x-1 dark:text-[#38383a]" />
    </Link>
  );
}
