"use client";
import { useCallback, useEffect, useState } from "react";
import { errorMessage } from "@/lib/format";
import { BarChart3, CheckCircle2, Flame, Loader2, RefreshCw, RotateCcw, type LucideIcon } from "lucide-react";
import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import { apiFetch } from "@/lib/client-api";
import { Alert, Button, Card, CardContent, CardHeader, CardTitle, PageHeader, Segmented } from "@/components/ui";

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
      <div className="liquid-glass rounded-[16px] p-3 text-xs shadow-[0_12px_36px_rgba(0,0,0,0.18)] backdrop-blur-2xl">
        <p className="font-bold text-label">{label}</p>
        <div className="mt-2 space-y-1 text-[13px]">
          <p className="text-accent flex items-center justify-between gap-4"><span>复习次数</span><b>{d.reviews}</b></p>
          <p className="text-success flex items-center justify-between gap-4"><span>正确答题</span><b>{d.correct}</b></p>
          <p className="text-secondary-label flex items-center justify-between gap-4"><span>做题正确率</span><b>{d.accuracy === null ? "—" : `${d.accuracy}%`}</b></p>
          <p className="text-tertiary-label flex items-center justify-between gap-4"><span>有效做题时长</span><b>{d.minutes} 分钟</b></p>
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
  return <div className="space-y-4 sm:space-y-6"><PageHeader title="学习统计" description="时长仅累计有效做题时间；切换后台、窗口失焦或连续 45 秒无操作时自动暂停。" action={<div className="flex flex-wrap items-center gap-2"><Segmented value={String(days)} onChange={(value) => setDays(Number(value))} options={[{ value: "7", label: "7 天" }, { value: "30", label: "30 天" }, { value: "90", label: "90 天" }, { value: "365", label: "一年" }]} /><Button variant="outline" onClick={() => void load()}><RefreshCw className="size-4" />刷新</Button></div>} />
    {error && <Alert>{error}</Alert>}
    {!data && !error && <div className="grid min-h-72 place-items-center"><Loader2 className="size-8 animate-spin text-accent" /></div>}
    {data && <><section className="grid grid-cols-2 gap-3 sm:gap-4 xl:grid-cols-4">{([
      { label: "累计复习", value: data.summary.totalReviews, icon: BarChart3, tone: "bg-accent/12 text-accent" },
      { label: "总正确率", value: data.summary.totalAccuracy === null ? "—" : `${data.summary.totalAccuracy}%`, icon: CheckCircle2, tone: "bg-success/12 text-success-deep" },
      { label: "连续学习", value: `${data.summary.streakDays} 天`, icon: Flame, tone: "bg-warning/12 text-warning" },
      { label: "活跃错词", value: data.summary.activeWrongWords, icon: RotateCcw, tone: "bg-danger/12 text-danger" },
    ] satisfies Array<{ label: string; value: string | number; icon: LucideIcon; tone: string }>).map((item) => <Card key={item.label} className="ios-lift"><CardContent className="flex items-center gap-4 pt-5"><span className={`grid size-12 place-items-center rounded-2xl shadow-[0_4px_12px_rgba(0,0,0,0.06)] backdrop-blur-sm ${item.tone}`}><item.icon className="size-6" /></span><div><p className="text-sm text-secondary-label">{item.label}</p><p className="text-2xl font-bold">{item.value}</p></div></CardContent></Card>)}</section>
    <section className="grid gap-4 sm:gap-5 lg:grid-cols-[1.5fr_.5fr]"><Card><CardHeader><CardTitle>每日复习趋势</CardTitle></CardHeader><CardContent><div className="h-52 w-full sm:h-80"><ResponsiveContainer width="100%" height="100%"><AreaChart data={data.daily}><defs><linearGradient id="reviews" x1="0" y1="0" x2="0" y2="1"><stop offset="5%" stopColor="var(--ll-accent)" stopOpacity={0.3} /><stop offset="95%" stopColor="var(--ll-accent)" stopOpacity={0.02} /></linearGradient></defs><CartesianGrid strokeDasharray="3 3" vertical={false} stroke="rgba(0,0,0,0.06)" /><XAxis dataKey="date" tickFormatter={(value: string) => value.slice(5)} fontSize={11} /><YAxis allowDecimals={false} fontSize={11} /><Tooltip content={<CustomChartTooltip />} /><Area type="monotone" dataKey="reviews" stroke="var(--ll-accent)" strokeWidth={2.5} fill="url(#reviews)" /><Area type="monotone" dataKey="correct" stroke="var(--ll-success)" strokeWidth={2} fill="transparent" /></AreaChart></ResponsiveContainer></div></CardContent></Card>
      <Card><CardHeader><CardTitle>熟练度分布</CardTitle></CardHeader><CardContent className="space-y-4">{data.mastery.map((item) => { const config = LEVELS[item.level] ?? { label: item.level, className: "bg-quaternary-label" }; const percent = totalMastery ? Math.round(item.count / totalMastery * 100) : 0; return <div key={item.level}><div className="flex items-center justify-between text-sm"><span className="flex items-center gap-2"><span className={`size-2.5 rounded-full shadow-[0_2px_6px_rgba(0,0,0,0.15)] ${config.className}`} />{config.label}</span><span className="font-medium">{item.count} <span className="text-xs text-tertiary-label font-normal">({percent}%)</span></span></div><div className="mt-2 h-2 overflow-hidden rounded-full bg-black/[0.05] shadow-[inset_0_1px_2px_rgba(0,0,0,0.06)] dark:bg-white/[0.08]"><div className={`h-full rounded-full shadow-[0_1px_4px_rgba(0,0,0,0.15)] ${config.className}`} style={{ width: `${percent}%` }} /></div></div>; })}</CardContent></Card></section>
    <Card><CardHeader><CardTitle>最近学习明细</CardTitle></CardHeader><CardContent><div className="space-y-2.5 sm:hidden">{[...data.daily].reverse().slice(0, 30).map((item) => <div key={item.date} className="glass-inner rounded-[16px] p-3"><div className="flex items-center justify-between"><b className="text-sm">{item.date}</b><span className="text-sm font-semibold text-accent">{item.reviews} 次</span></div><div className="mt-2 grid grid-cols-3 gap-2 text-xs text-secondary-label"><span>正确 {item.correct}</span><span>正确率 {item.accuracy === null ? "—" : `${item.accuracy}%`}</span><span>有效 {item.minutes} 分钟</span><span className="text-danger">忘记 {item.again}</span><span className="text-warning">跳过 {item.skipped}</span><span>会话 {item.sessions}</span></div></div>)}</div><div className="hidden overflow-auto glass-inner rounded-[18px] sm:block dark:border-white/[0.08]"><table className="w-full min-w-[640px] text-left text-sm"><thead className="bg-white/50 text-xs text-secondary-label backdrop-blur-xl dark:bg-white/[0.04] dark:text-secondary-label"><tr><th className="p-3">日期</th><th className="p-3">复习</th><th className="p-3">正确</th><th className="p-3">正确率</th><th className="p-3">忘记</th><th className="p-3">稍后再学</th><th className="p-3">有效做题时长</th><th className="p-3">会话</th></tr></thead><tbody>{[...data.daily].reverse().slice(0, 30).map((item) => <tr key={item.date} className="border-t border-black/[0.04] dark:border-white/[0.06]"><td className="p-3 font-medium">{item.date}</td><td className="p-3">{item.reviews}</td><td className="p-3 text-success">{item.correct}</td><td className="p-3">{item.accuracy === null ? "—" : `${item.accuracy}%`}</td><td className="p-3 text-danger">{item.again}</td><td className="p-3 text-warning">{item.skipped}</td><td className="p-3">{item.minutes} 分钟</td><td className="p-3">{item.sessions}</td></tr>)}</tbody></table></div></CardContent></Card></>}
  </div>;
}
