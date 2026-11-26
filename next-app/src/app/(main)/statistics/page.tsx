"use client";
import { useCallback, useEffect, useState } from "react";
import { errorMessage } from "@/lib/format";
import { BarChart3, CheckCircle2, Flame, Loader2, RefreshCw, RotateCcw, type LucideIcon } from "lucide-react";
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { apiFetch } from "@/lib/client-api";
import { Alert, AnimatedCounter, Button, Card, CardContent, CardHeader, CardTitle, PageHeader, Segmented } from "@/components/ui";

interface Statistics {
  summary: { totalReviews: number; totalAccuracy: number | null; streakDays: number; activeWrongWords: number };
  daily: Array<{ date: string; reviews: number; correct: number; again: number; skipped: number; minutes: number; sessions: number; accuracy: number | null }>;
  mastery: Array<{ level: string; count: number }>;
}

function CustomChartTooltip({ active, payload, label }: { active?: boolean; payload?: Array<{ payload: Statistics["daily"][number] }>; label?: string }) {
  if (active && payload && payload.length) {
    const d = payload[0]?.payload;
    if (!d) return null;
    return (
      <div className="liquid-glass rounded-[14px] p-3 text-xs shadow-[0_8px_24px_-4px_rgba(0,0,0,0.12)]">
        <p className="font-semibold text-label">{label}</p>
        <div className="mt-2 space-y-1 text-xs num-tabular">
          <p className="text-accent flex items-center justify-between gap-4"><span>复习次数</span><b className="font-semibold">{d.reviews}</b></p>
          <p className="text-success flex items-center justify-between gap-4"><span>正确答题</span><b className="font-semibold">{d.correct}</b></p>
          <p className="text-secondary-label flex items-center justify-between gap-4"><span>做题正确率</span><b className="font-semibold">{d.accuracy === null ? "—" : `${d.accuracy}%`}</b></p>
          <p className="text-tertiary-label flex items-center justify-between gap-4"><span>有效做题时长</span><b className="font-semibold">{d.minutes} 分钟</b></p>
        </div>
      </div>
    );
  }
  return null;
}

const LEVELS: Record<string, { label: string; className: string }> = { NEW: { label: "新词", className: "bg-quaternary-label" }, LEARNING: { label: "学习中", className: "bg-accent" }, FAMILIAR: { label: "熟悉", className: "bg-success" }, PROFICIENT: { label: "熟练", className: "bg-purple" }, MASTERED: { label: "已掌握", className: "bg-[#5856d6]" } };
export default function StatisticsPage() {
  const [days, setDays] = useState(30); const [data, setData] = useState<Statistics | null>(null); const [error, setError] = useState("");
  const load = useCallback(async () => { try { setData(await apiFetch<Statistics>(`/api/statistics?days=${days}`)); setError(""); } catch (reason) { setError(errorMessage(reason, "加载失败")); } }, [days]);
  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer); }, [load]);
  const totalMastery = data?.mastery.reduce((sum, item) => sum + item.count, 0) ?? 0;
  return <div className="space-y-4 sm:space-y-5"><PageHeader title="学习统计" description="时长仅累计有效做题时间；切换后台、窗口失焦或连续 45 秒无操作时自动暂停。" action={<div className="flex flex-wrap items-center gap-2"><Segmented value={String(days)} onChange={(value) => setDays(Number(value))} options={[{ value: "7", label: "7 天" }, { value: "30", label: "30 天" }, { value: "90", label: "90 天" }, { value: "365", label: "一年" }]} /><Button variant="outline" onClick={() => void load()}><RefreshCw className="size-4" />刷新</Button></div>} />
    {error && <Alert>{error}</Alert>}
    {!data && !error && <div className="grid min-h-72 place-items-center"><Loader2 className="size-8 animate-spin text-accent" /></div>}
    {data && <><section className="grid grid-cols-2 gap-2.5 sm:gap-3.5 xl:grid-cols-4">{([
      { label: "累计复习", value: data.summary.totalReviews, isNumber: true, icon: BarChart3, tone: "bg-accent/10 text-accent" },
      { label: "总正确率", value: data.summary.totalAccuracy === null ? "—" : `${data.summary.totalAccuracy}%`, isNumber: false, icon: CheckCircle2, tone: "bg-success/10 text-success-deep" },
      { label: "连续学习", value: `${data.summary.streakDays} 天`, isNumber: false, icon: Flame, tone: "bg-warning/10 text-warning" },
      { label: "活跃错词", value: data.summary.activeWrongWords, isNumber: true, icon: RotateCcw, tone: "bg-danger/10 text-danger" },
    ] satisfies Array<{ label: string; value: string | number; isNumber: boolean; icon: LucideIcon; tone: string }>).map((item) => <Card key={item.label} className="liquid-glass-interactive"><CardContent className="flex items-center gap-3.5 pt-4 sm:pt-4.5"><span className={`grid size-11 place-items-center rounded-[13px] shadow-xs backdrop-blur-sm ${item.tone}`}><item.icon className="size-5" /></span><div><p className="text-xs font-medium text-secondary-label">{item.label}</p><p className="num-tabular text-xl font-bold tracking-tight sm:text-2xl">{typeof item.value === "number" ? <AnimatedCounter value={item.value} /> : item.value}</p></div></CardContent></Card>)}</section>
    <section className="grid gap-4 sm:gap-5 lg:grid-cols-[1.5fr_.5fr]"><Card><CardHeader><CardTitle>每日复习趋势</CardTitle></CardHeader><CardContent><div className="h-52 w-full sm:h-80"><ResponsiveContainer width="100%" height="100%"><AreaChart data={data.daily}><defs><linearGradient id="reviews" x1="0" y1="0" x2="0" y2="1"><stop offset="5%" stopColor="var(--ll-accent)" stopOpacity={0.25} /><stop offset="95%" stopColor="var(--ll-accent)" stopOpacity={0.01} /></linearGradient></defs><CartesianGrid strokeDasharray="3 3" vertical={false} stroke="rgba(0,0,0,0.05)" /><XAxis dataKey="date" tickFormatter={(value: string) => value.slice(5)} fontSize={11} /><YAxis allowDecimals={false} fontSize={11} /><Tooltip content={<CustomChartTooltip />} /><Area type="monotone" dataKey="reviews" stroke="var(--ll-accent)" strokeWidth={2} fill="url(#reviews)" /><Area type="monotone" dataKey="correct" stroke="var(--ll-success)" strokeWidth={1.5} fill="transparent" /></AreaChart></ResponsiveContainer></div></CardContent></Card>
      <Card><CardHeader><CardTitle>熟练度分布</CardTitle></CardHeader><CardContent className="space-y-3.5">{data.mastery.map((item) => { const config = LEVELS[item.level] ?? { label: item.level, className: "bg-quaternary-label" }; const percent = totalMastery ? Math.round(item.count / totalMastery * 100) : 0; return <div key={item.level}><div className="flex items-center justify-between text-xs sm:text-sm"><span className="flex items-center gap-2"><span className={`size-2 rounded-full ${config.className}`} />{config.label}</span><span className="num-tabular font-medium">{item.count} <span className="text-xs text-tertiary-label font-normal">({percent}%)</span></span></div><div className="mt-1.5 h-1.5 overflow-hidden rounded-full bg-black/[0.05] dark:bg-white/[0.08]"><div className={`h-full rounded-full ${config.className}`} style={{ width: `${percent}%` }} /></div></div>; })}</CardContent></Card></section>
    <Card><CardHeader><CardTitle>最近学习明细</CardTitle></CardHeader><CardContent><div className="space-y-2 sm:hidden">{[...data.daily].reverse().slice(0, 30).map((item) => <div key={item.date} className="glass-inner rounded-[14px] p-3"><div className="flex items-center justify-between"><b className="text-[13.5px]">{item.date}</b><span className="num-tabular text-[13.5px] font-semibold text-accent">{item.reviews} 次</span></div><div className="mt-2 grid grid-cols-3 gap-2 text-xs text-secondary-label num-tabular"><span>正确 {item.correct}</span><span>正确率 {item.accuracy === null ? "—" : `${item.accuracy}%`}</span><span>有效 {item.minutes} 分钟</span><span className="text-danger">忘记 {item.again}</span><span className="text-warning">跳过 {item.skipped}</span><span>会话 {item.sessions}</span></div></div>)}</div><div className="hidden overflow-auto glass-inner rounded-[16px] sm:block dark:border-white/[0.08]"><table className="w-full min-w-[640px] text-left text-[13.5px]"><thead className="bg-white/60 text-xs text-secondary-label backdrop-blur-xl dark:bg-white/[0.04] dark:text-secondary-label"><tr><th className="p-3 font-semibold">日期</th><th className="p-3 font-semibold">复习</th><th className="p-3 font-semibold">正确</th><th className="p-3 font-semibold">正确率</th><th className="p-3 font-semibold">忘记</th><th className="p-3 font-semibold">稍后再学</th><th className="p-3 font-semibold">有效做题时长</th><th className="p-3 font-semibold">会话</th></tr></thead><tbody className="num-tabular">{[...data.daily].reverse().slice(0, 30).map((item) => <tr key={item.date} className="border-t border-black/[0.04] transition-colors hover:bg-black/[0.02] dark:border-white/[0.06] dark:hover:bg-white/[0.03]"><td className="p-3 font-medium">{item.date}</td><td className="p-3">{item.reviews}</td><td className="p-3 text-success font-medium">{item.correct}</td><td className="p-3">{item.accuracy === null ? "—" : `${item.accuracy}%`}</td><td className="p-3 text-danger font-medium">{item.again}</td><td className="p-3 text-warning font-medium">{item.skipped}</td><td className="p-3">{item.minutes} 分钟</td><td className="p-3">{item.sessions}</td></tr>)}</tbody></table></div></CardContent></Card></>}
  </div>;
}

