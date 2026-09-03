"use client";
import Link from "next/link";
import { errorMessage } from "@/lib/format";
import { useCallback, useEffect, useState } from "react";
import { AlertCircle, ArrowRight, AudioLines, Blocks, BookOpen, Brain, CheckCircle2, Clock3, Gamepad2, GraduationCap, Hammer, Headphones, Layers, Loader2, MessageSquareText, PenLine, Puzzle, RefreshCw, RotateCcw, Sparkles, Upload } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { Badge, Card, CardContent, CardHeader, CardTitle, EmptyState, buttonClass } from "@/components/ui";
import { DailyAiSuggestion } from "./daily-ai-suggestion";

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
  resumeSession: null | { id: number; sessionType: string; startedAt: string; remainingCount: number; plannedCount: number };
  plan: {
    dueReviewCount: number; plannedDueReviewCount: number;
    wrongWordCount: number; plannedWrongWordCount: number;
    newWordCount: number; plannedNewWordCount: number;
    sentenceReviewCount: number; plannedSentenceReviewCount: number;
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
      setError(errorMessage(reason, "加载失败"));
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
          <Loader2 className="mx-auto size-10 animate-spin text-accent" />
          <p className="mt-3 text-[15px] text-quaternary-label">正在加载…</p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <EmptyState
        icon={<AlertCircle className="size-10 text-danger" />}
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
            <div className="grid size-20 place-items-center rounded-[24px] bg-gradient-to-br from-accent to-[#5856d6] text-white shadow-[0_8px_24px_rgba(0,122,255,0.3)]">
              <BookOpen className="size-10" />
            </div>
          }
          title="从 EasyDict 收藏开始"
          description="导入 EasyDict Favorites CSV。LexiLoop 只初始化你实际收藏的词条，不会导入整本词典。"
          action={<Link href="/add?tab=csv" className={buttonClass("primary", "lg")}><Upload className="size-5" />导入 CSV</Link>}
        />
      </div>
    );
  }

  const completedToday = data.todayProcessed;
  const planProgress = data.todayGoalTotal ? (completedToday / data.todayGoalTotal) * 100 : 100;

  return (
    <div className="space-y-4 sm:space-y-5">
      {/* Hero Card */}
      <section className="animate-fade-up relative overflow-hidden rounded-[24px] bg-gradient-to-br from-[#007aff] via-[#5856d6] to-[#af52de] p-5 text-white shadow-[0_12px_40px_-8px_rgba(0,122,255,0.32),inset_0_1.5px_0_rgba(255,255,255,0.3)] sm:rounded-[28px] sm:p-8">
        <div className="absolute -right-16 -top-16 size-52 rounded-full bg-white/[0.12] blur-2xl pointer-events-none" />
        <div className="absolute -bottom-14 -left-14 size-40 rounded-full bg-white/[0.08] blur-xl pointer-events-none" />
        <div className="relative flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between sm:gap-6">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <Badge tone="glass">今日学习</Badge>
              {completedToday >= (data.todayGoalTotal || 1) && data.todayGoalTotal > 0 && (
                <Badge tone="glass" className="border-success/40 bg-success/20 text-white">今日目标已达成 🎉</Badge>
              )}
            </div>
            <h1 className="mt-2.5 text-[22px] font-bold leading-tight tracking-tight sm:mt-3.5 sm:text-[28px]">
              保持词汇循环，不让记忆掉队
            </h1>
            <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-white/75 sm:text-[14.5px]">
              {completedToday >= data.todayGoalTotal && data.todayGoalTotal > 0
                ? `今日计划任务已全部完成！已处理 ${completedToday} 个任务，继续保持。`
                : `今天还剩 ${data.plan.plannedTotal} 个任务，预计 ${data.plan.estimatedMinutes} 分钟。`}
            </p>
          </div>
          <Link
            href="/study?mode=DAILY"
            className="ios-press inline-flex h-11 w-full shrink-0 items-center justify-center gap-2 rounded-2xl bg-white px-6 text-[15px] font-semibold text-accent shadow-[0_4px_16px_rgba(0,0,0,0.12)] transition-all hover:bg-white/95 sm:h-[48px] sm:w-auto sm:px-7 sm:text-[16px]"
          >
            <Sparkles className="size-4.5" />
            {completedToday >= data.todayGoalTotal && data.todayGoalTotal > 0 ? "继续无限学习" : "开始学习"}
            <ArrowRight className="size-4.5" />
          </Link>
        </div>
        <div className="relative mt-5 sm:mt-6">
          <div className="mb-2 flex justify-between text-xs font-medium text-white/70">
            <span>今日完成度</span>
            <span className="num-tabular">{completedToday}/{data.todayGoalTotal} ({Math.round(planProgress)}%)</span>
          </div>
          <div className="h-[6px] overflow-hidden rounded-full bg-white/[0.2] shadow-[inset_0_1px_2px_rgba(0,0,0,0.1)]">
            <div
              className="h-full rounded-full bg-white shadow-[0_1px_4px_rgba(255,255,255,0.4)] transition-all duration-500 ease-out"
              style={{ width: `${Math.min(100, planProgress)}%` }}
            />
          </div>
        </div>
      </section>

      {data.resumeSession && (
        <Link href={`/study?mode=${encodeURIComponent(data.resumeSession.sessionType)}`} className="ios-press glass-inner flex items-center gap-3 rounded-[18px] p-3.5 transition-shadow hover:shadow-[0_8px_24px_rgba(0,122,255,0.08)] sm:rounded-[20px] sm:p-4.5">
          <span className="grid size-9.5 shrink-0 place-items-center rounded-[12px] bg-accent/10 text-accent"><Clock3 className="size-4.5" /></span>
          <span className="min-w-0 flex-1"><b className="block text-[14.5px] font-semibold">继续上次学习</b><small className="mt-0.5 block text-[13px] text-secondary-label">{sessionLabel(data.resumeSession.sessionType)} · 还剩 {data.resumeSession.remainingCount} 题</small></span>
          <span className="inline-flex items-center gap-1 text-[13.5px] font-semibold text-accent">继续<ArrowRight className="size-4" /></span>
        </Link>
      )}

      <DailyAiSuggestion />

      {/* Today's queue */}
      <section className="space-y-4 sm:space-y-5">
        <Card className="animate-fade-up stagger-3">
          <CardHeader><CardTitle>今日队列</CardTitle></CardHeader>
          <CardContent className="grid gap-2.5 sm:grid-cols-3 sm:gap-3">
            <QueueCard icon={<RotateCcw className="size-4.5" />} label="到期复习" count={data.plan.dueReviewCount} planned={data.plan.plannedDueReviewCount} href="/study?mode=DUE_REVIEW" gradient="from-accent to-[#5ac8fa]" />
            <QueueCard icon={<AlertCircle className="size-4.5" />} label="错词强化" count={data.plan.wrongWordCount} planned={data.plan.plannedWrongWordCount} href="/study?mode=WRONG_WORDS" gradient="from-danger to-[#ff6961]" />
            <QueueCard icon={<Sparkles className="size-4.5" />} label="新词学习" count={data.plan.newWordCount} planned={data.plan.plannedNewWordCount} href="/study?mode=NEW_WORDS" gradient="from-purple to-[#af52de]" />
          </CardContent>
        </Card>

        {/* Stats */}
        <section className="grid grid-cols-2 gap-2.5 sm:gap-3.5 xl:grid-cols-4">
          {[
            { label: "总词数", value: data.totalWords, detail: `${data.initializedWords} 个可学习`, icon: BookOpen, gradient: "from-accent to-[#5ac8fa]" },
            { label: "已掌握", value: data.masteredWords, detail: `${Math.round((data.masteredWords / Math.max(1, data.totalWords)) * 100)}% 掌握率`, icon: CheckCircle2, gradient: "from-success to-[#30d158]" },
            { label: "今日已处理", value: data.todayProcessed, detail: data.todayAccuracy === null ? `${data.todaySkipped} 个稍后再学` : `${data.todayAccuracy}% 正确率`, icon: Brain, gradient: "from-purple to-[#bf5af2]" },
            { label: "初始化异常", value: data.failedWords, detail: data.failedWords ? "建议前往处理" : "状态正常", icon: AlertCircle, gradient: data.failedWords ? "from-danger to-[#ff6961]" : "from-quaternary-label to-tertiary-label" },
          ].map((item, index) => (
            <Card key={item.label} className={`ios-lift animate-fade-up stagger-${index + 1}`}>
              <CardContent className="flex items-center gap-3 pt-3.5 sm:gap-3.5 sm:pt-4.5">
                <div className={`grid size-9.5 place-items-center rounded-[11px] bg-gradient-to-br ${item.gradient} text-white shadow-sm sm:size-11 sm:rounded-[13px]`}>
                  <item.icon className="size-4.5 sm:size-5" />
                </div>
                <div>
                  <p className="text-[12px] font-medium text-quaternary-label dark:text-[#636366]">{item.label}</p>
                  <p className="num-tabular text-[20px] font-bold tracking-tight sm:text-[24px]">{item.value}</p>
                  <p className="hidden text-xs text-tertiary-label dark:text-[#545458] sm:block">{item.detail}</p>
                </div>
              </CardContent>
            </Card>
          ))}
        </section>

        <Card className="animate-fade-up stagger-4">
          <CardHeader><CardTitle>专项练习</CardTitle></CardHeader>
          <CardContent className="grid gap-2 sm:grid-cols-3 sm:gap-3">
            <PracticeLink
              href="/study?mode=LISTENING"
              icon={<Headphones className="size-4.5" />}
              title="听力拼写"
              subtitle="听发音后输入词条"
              gradient="from-[#5ac8fa] to-accent"
            />
            <PracticeLink
              href="/study?mode=SPELLING"
              icon={<PenLine className="size-4.5" />}
              title="中文拼写"
              subtitle="根据释义回忆英文"
              gradient="from-warning to-[#ff6961]"
            />
            <PracticeLink
              href="/study?mode=SENTENCE_REVIEW"
              icon={<MessageSquareText className="size-4.5" />}
              title="句子复习"
              subtitle={`理解与还原完整句子 · ${data.plan.sentenceReviewCount} 个待练`}
              gradient="from-[#5856d6] to-purple"
            />
          </CardContent>
        </Card>
      </section>

      <Card className="animate-fade-up stagger-5">
        <CardHeader className="flex-row items-center justify-between gap-3">
          <div className="flex items-center gap-2.5">
            <span className="grid size-8 place-items-center rounded-[10px] bg-gradient-to-br from-[#5856d6] to-[#00c7be] text-white"><GraduationCap className="size-4.5" /></span>
            <div><CardTitle>音标学习</CardTitle><p className="mt-0.5 text-xs text-quaternary-label">48 音标 · 讲透会区分 + 美英对照</p></div>
          </div>
          <Link href="/phonetics" className="hidden sm:inline-flex items-center gap-1 text-xs font-semibold text-accent">查看全部<ArrowRight className="size-3.5" /></Link>
        </CardHeader>
        <CardContent className="space-y-2.5">
          <div className="grid gap-2 sm:grid-cols-3">
            <Link href="/phonetics" className="ios-press group flex items-center gap-3 rounded-[16px] border border-accent/15 bg-accent/[0.06] p-3.5 hover:bg-accent/[0.08]">
              <span className="grid size-10 place-items-center rounded-[12px] bg-gradient-to-br from-[#5856d6] to-accent text-white"><GraduationCap className="size-5" /></span>
              <span className="min-w-0 flex-1 text-left"><b className="block text-[14px]">音标学习专区</b><small className="text-xs text-secondary-label">48 音标 · 逐个讲透 + 跟读</small></span>
              <ArrowRight className="size-4 text-accent transition group-hover:translate-x-0.5" />
            </Link>
            <Link href="/phonetics" className="ios-press group flex items-center gap-3 rounded-[16px] bg-black/[0.03] p-3.5 hover:bg-black/[0.05] dark:bg-white/[0.04]">
              <span className="grid size-10 place-items-center rounded-[12px] bg-[#00c7be]/10 text-[#00a59d]"><Layers className="size-5" /></span>
              <span className="min-w-0 flex-1 text-left"><b className="block text-[14px]">音素表</b><small className="text-xs text-quaternary-label">分类卡片 · 搜 /æ/ /θ/ 试听</small></span>
              <ArrowRight className="size-4 text-quaternary-label" />
            </Link>
            <Link href="/phonetics" className="ios-press group flex items-center gap-3 rounded-[16px] bg-black/[0.03] p-3.5 hover:bg-black/[0.05] dark:bg-white/[0.04]">
              <span className="grid size-10 place-items-center rounded-[12px] bg-warning/10 text-warning"><Headphones className="size-5" /></span>
              <span className="min-w-0 flex-1 text-left"><b className="block text-[14px]">易混对比</b><small className="text-xs text-quaternary-label">最小对立 · 盲听分辨</small></span>
              <ArrowRight className="size-4 text-quaternary-label" />
            </Link>
          </div>
          <Link href="/phonetics" className="ios-press flex sm:hidden w-full items-center justify-center gap-1 rounded-[12px] border border-black/[0.06] bg-white/70 py-2.5 text-sm font-semibold text-accent dark:border-white/[0.08] dark:bg-white/[0.05]">进入音标学习专区<ArrowRight className="size-4" /></Link>
        </CardContent>
      </Card>

      <Card className="animate-fade-up stagger-5">
        <CardHeader className="flex-row items-center justify-between gap-3">
          <div><CardTitle>趣味训练</CardTitle><p className="mt-0.5 text-xs text-quaternary-label">独立游戏模式，不占用今日复习队列</p></div>
        </CardHeader>
        <CardContent className="grid grid-cols-2 gap-2 sm:gap-3 lg:grid-cols-4">
          <PracticeLink dense href="/match" icon={<Gamepad2 className="size-4.5" />} title="限时词汇配对" subtitle="英文与释义组队" gradient="from-purple to-[#5856d6]" />
          <PracticeLink dense href="/phonetics" icon={<AudioLines className="size-4.5" />} title="音标辨音训练" subtitle="听音、音标与拼写" gradient="from-[#00c7be] to-accent" />
          <PracticeLink dense href="/games?mode=WORD_BUILDER" icon={<Puzzle className="size-4.5" />} title="单词拼图" subtitle="点击字母完成拼写" gradient="from-warning to-[#ff6961]" />
          <PracticeLink dense href="/games?mode=LISTENING_PICK" icon={<Headphones className="size-4.5" />} title="听音辨词" subtitle="听发音快速选词" gradient="from-[#5ac8fa] to-accent" />
          <PracticeLink dense href="/games?mode=MEANING_BLITZ" icon={<Brain className="size-4.5" />} title="词义冲刺" subtitle="限时选择正确释义" gradient="from-success to-accent" />
          <PracticeLink dense href="/games?mode=WHACK_A_MOLE" icon={<Hammer className="size-4.5" />} title="词汇地鼠" subtitle="锤出正确单词" gradient="from-success to-[#00c7be]" />
          <PracticeLink dense href="/games?mode=WORD_STACK" icon={<Layers className="size-4.5" />} title="单词堆堆乐" subtitle="点词块搭高塔" gradient="from-[#ff2d55] to-warning" />
          <PracticeLink dense href="/games?mode=WORD_TETRIS" icon={<Blocks className="size-4.5" />} title="词汇俄罗斯方块" subtitle="点中下落的正确单词" gradient="from-[#5856d6] to-purple" />
        </CardContent>
      </Card>
    </div>
  );
}

function QueueCard({ icon, label, count, planned, href, gradient }: {
  icon: React.ReactNode; label: string; count: number; planned: number; href: string; gradient: string;
}) {
  return (
    <Link href={href} className="ios-press group glass-inner flex items-center gap-3 rounded-[16px] p-3 transition-all duration-200 hover:shadow-[0_8px_24px_rgba(0,0,0,0.04)] dark:hover:shadow-[0_8px_24px_rgba(0,0,0,0.2)] sm:block sm:rounded-[18px] sm:p-4.5">
      <div className="flex shrink-0 items-center justify-between sm:justify-between">
        <span className={`grid size-9.5 place-items-center rounded-[12px] bg-gradient-to-br ${gradient} text-white shadow-xs`}>{icon}</span>
        <ArrowRight className="hidden size-4 text-[#c7c7cc] transition-transform duration-200 group-hover:translate-x-1 sm:block dark:text-[#545458]" />
      </div>
      <div className="min-w-0 flex-1 sm:mt-4"><p className="num-tabular text-[22px] font-bold leading-none tracking-tight sm:text-[26px]">{planned}</p><p className="mt-1 text-[13px] font-semibold text-label">{label}</p><p className="mt-0.5 text-xs text-tertiary-label dark:text-[#545458]">共 {count} 个待处理</p></div>
      <ArrowRight className="size-4 shrink-0 text-[#c7c7cc] transition-transform duration-200 group-hover:translate-x-1 sm:hidden dark:text-[#545458]" />
    </Link>
  );
}

function PracticeLink({ href, icon, title, subtitle, gradient, dense = false }: {
  href: string; icon: React.ReactNode; title: string; subtitle: string; gradient: string; dense?: boolean;
}) {
  return (
    <Link href={href} className={`ios-press group glass-inner flex items-center justify-between rounded-[16px] p-3 transition-all duration-200 hover:shadow-[0_8px_24px_rgba(0,0,0,0.04)] dark:hover:shadow-[0_8px_24px_rgba(0,0,0,0.2)] sm:rounded-[18px] sm:p-4 ${dense ? "max-sm:flex-col max-sm:items-start max-sm:gap-2" : ""}`}>
      <span className={`flex items-center gap-3 ${dense ? "min-w-0 max-sm:w-full" : ""}`}>
        <span className={`grid size-9 shrink-0 place-items-center rounded-[11px] bg-gradient-to-br ${gradient} text-white shadow-xs sm:size-10 sm:rounded-[13px]`}>{icon}</span>
        <span className="min-w-0">
          <b className="block truncate text-[14.5px] font-semibold tracking-tight">{title}</b>
          <small className="block truncate text-[12.5px] text-quaternary-label dark:text-[#636366]">{subtitle}</small>
        </span>
      </span>
      <ArrowRight className={`size-4 shrink-0 text-[#c7c7cc] transition-transform duration-200 group-hover:translate-x-1 dark:text-[#545458] ${dense ? "max-sm:hidden" : ""}`} />
    </Link>
  );
}

function sessionLabel(sessionType: string): string {
  return ({ DAILY: "今日学习", NEW_WORDS: "新词学习", DUE_REVIEW: "到期复习", WRONG_WORDS: "错词强化", LISTENING: "听力拼写", SPELLING: "中文拼写", SENTENCE_REVIEW: "句子复习", AI_RECOMMENDED: "AI 今日必做题" } as Record<string, string>)[sessionType] ?? "学习会话";
}

