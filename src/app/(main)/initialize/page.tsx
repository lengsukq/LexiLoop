"use client";
import Link from "next/link";
import { useCallback, useEffect, useMemo, useState } from "react";
import { AlertCircle, CheckCircle2, Clock3, Loader2, RefreshCw, RotateCcw, Server, Sparkles, XCircle, type LucideIcon } from "lucide-react";
import { apiFetch, formatDate } from "@/lib/client-api";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, EmptyState, PageHeader, Progress } from "@/components/ui";
import { InitializationBadge } from "@/components/status-badges";

interface StatusData { summary: Record<string, number>; workers: Array<{ workerId: string; status: string; currentJobId: number | null; lastSeenAt: string; startedAt: string }>; }
interface Job { id: number; wordId: number; term: string; status: string; mode: string; priority: number; attemptCount: number; maxAttempts: number; lastError: string | null; lastErrorCode: string | null; createdAt: string; updatedAt: string; completedAt: string | null; }

export default function InitializePage() {
  const [status, setStatus] = useState<StatusData | null>(null);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [filter, setFilter] = useState("");
  const [error, setError] = useState("");
  const [retrying, setRetrying] = useState(false);
  const [bulkBusy, setBulkBusy] = useState<"fill" | "force" | "">("");
  const [bulkMessage, setBulkMessage] = useState("");
  const load = useCallback(async () => {
    try {
      const query = filter ? `?status=${filter}` : "";
      const [statusData, jobData] = await Promise.all([apiFetch<StatusData>("/api/initialization/status"), apiFetch<Job[]>(`/api/initialization${query}`)]);
      setStatus(statusData); setJobs(jobData); setError("");
    } catch (reason) { setError(reason instanceof Error ? reason.message : "加载失败"); }
  }, [filter]);
  useEffect(() => { const initial = window.setTimeout(() => void load(), 0); const timer = window.setInterval(() => void load(), 3000); return () => { window.clearTimeout(initial); window.clearInterval(timer); }; }, [load]);
  const total = useMemo(() => status ? Object.values(status.summary).reduce((sum, value) => sum + value, 0) : 0, [status]);
  const completed = (status?.summary.READY ?? 0) + (status?.summary.PARTIAL ?? 0);
  async function retryFailed() {
    const ids = jobs.filter((job) => job.status === "FAILED").map((job) => job.id);
    if (!ids.length) return;
    setRetrying(true);
    try { await apiFetch("/api/initialization/retry", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ jobIds: ids }) }); await load(); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "重试失败"); }
    finally { setRetrying(false); }
  }
  async function queueBulk(force: boolean) {
    if (force && !window.confirm("强制重新生成会让所有词条再次调用大模型，可能产生较多 Token 消耗。确定继续吗？")) return;
    setBulkBusy(force ? "force" : "fill");
    setBulkMessage("");
    setError("");
    try {
      const result = await apiFetch<{
        totalWords: number;
        selectedWords: number;
        skippedAiInitialized: number;
        createdJobs: number;
        updatedJobs: number;
      }>("/api/initialization/bulk", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          mode: force ? "FORCE_OVERWRITE" : "FILL_MISSING_FIELDS",
          onlyWithoutAi: !force,
        }),
      });
      setBulkMessage(force
        ? `已为 ${result.selectedWords} 个词条创建或升级强制 AI 初始化任务。`
        : `已选择 ${result.selectedWords} 个尚未成功经过 AI 的词条；新增任务 ${result.createdJobs} 个，升级任务 ${result.updatedJobs} 个，跳过已完成 ${result.skippedAiInitialized} 个。`);
      await load();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "批量初始化失败");
    } finally {
      setBulkBusy("");
    }
  }
  return <div className="space-y-6"><PageHeader title="词条初始化" description="内置后台引擎使用 AI 生成完整词汇学习内容，DictionaryAPI/ECDICT 补充音标和词形，Edge TTS 按需负责发音。" action={<Button variant="outline" onClick={() => void load()}><RefreshCw className="size-4" />刷新</Button>} />
    {status && <><div className="grid grid-cols-2 gap-3 lg:grid-cols-6">{([
      { label: "排队", value: status.summary.QUEUED ?? 0, icon: Clock3, color: "text-sky-600" },
      { label: "处理中", value: status.summary.RUNNING ?? 0, icon: Loader2, color: "text-indigo-600" },
      { label: "就绪", value: status.summary.READY ?? 0, icon: CheckCircle2, color: "text-emerald-600" },
      { label: "部分完成", value: status.summary.PARTIAL ?? 0, icon: AlertCircle, color: "text-amber-600" },
      { label: "失败", value: status.summary.FAILED ?? 0, icon: XCircle, color: "text-rose-600" },
      { label: "总任务", value: total, icon: Server, color: "text-slate-600" },
    ] satisfies Array<{ label: string; value: number; icon: LucideIcon; color: string }>).map((item) => <Card key={item.label}><CardContent className="pt-5"><item.icon className={`size-5 ${item.color} ${item.label === "处理中" && item.value > 0 ? "animate-spin" : ""}`} /><p className="mt-3 text-2xl font-bold">{item.value}</p><p className="text-xs text-slate-500">{item.label}</p></CardContent></Card>)}</div><Card><CardContent className="pt-5"><div className="flex items-center justify-between text-sm"><span>总体完成度</span><span>{completed}/{total}</span></div><Progress value={completed} max={Math.max(1, total)} className="mt-3" /></CardContent></Card></>}
    <Card><CardHeader><div><CardTitle className="flex items-center gap-2"><Sparkles className="size-5 text-violet-500" />批量 AI 初始化</CardTitle><p className="mt-1 text-sm text-slate-500">默认只处理尚未成功经过 AI 的词条；强制模式会重新生成所有词条，但仍保留手动释义。</p></div></CardHeader><CardContent><div className="flex flex-wrap gap-3"><Button onClick={() => void queueBulk(false)} disabled={Boolean(bulkBusy)}>{bulkBusy === "fill" ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}补全所有未经过 AI 的词条</Button><Button variant="outline" onClick={() => void queueBulk(true)} disabled={Boolean(bulkBusy)}>{bulkBusy === "force" ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}强制重新生成全部</Button></div>{bulkMessage && <div className="mt-4 rounded-xl bg-emerald-50 p-3 text-sm text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-300">{bulkMessage}</div>}<p className="mt-3 text-xs text-slate-400">执行前请先在「设置 → 大模型配置」中启用 AI 词条初始化并配置 API Key、接口地址和模型。</p></CardContent></Card>
    <Card><CardHeader><div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"><CardTitle>内置后台引擎状态</CardTitle>{jobs.some((job) => job.status === "FAILED") && <Button variant="outline" onClick={() => void retryFailed()} disabled={retrying}>{retrying ? <Loader2 className="size-4 animate-spin" /> : <RotateCcw className="size-4" />}重试当前失败任务</Button>}</div></CardHeader><CardContent>{status?.workers.length ? <div className="grid gap-3 sm:grid-cols-2">{status.workers.map((worker) => <div key={worker.workerId} className="rounded-2xl border border-slate-200 p-4 dark:border-slate-700"><div className="flex items-center justify-between"><b className="text-sm">{worker.workerId}</b><Badge tone={worker.status === "ERROR" ? "red" : worker.status === "WORKING" ? "blue" : "green"}>{worker.status}</Badge></div><p className="mt-2 text-xs text-slate-500">最后心跳：{formatDate(worker.lastSeenAt)}</p>{worker.currentJobId && <p className="mt-1 text-xs text-slate-500">当前任务：#{worker.currentJobId}</p>}</div>)}</div> : <div className="rounded-xl bg-amber-50 p-4 text-sm text-amber-700 dark:bg-amber-950/30 dark:text-amber-300">尚未检测到内置后台引擎心跳。主程序启动后会自动运行；若持续无心跳，请检查 BACKGROUND_ENGINE_ENABLED 配置和主程序日志。</div>}</CardContent></Card>
    <Card><CardHeader><div className="flex flex-wrap items-center justify-between gap-3"><CardTitle>任务记录</CardTitle><select className="h-9 rounded-xl border border-slate-200 bg-white px-3 text-sm dark:border-slate-700 dark:bg-slate-950" value={filter} onChange={(event) => setFilter(event.target.value)}><option value="">全部状态</option><option value="QUEUED">排队</option><option value="RUNNING">处理中</option><option value="READY">就绪</option><option value="PARTIAL">部分完成</option><option value="FAILED">失败</option></select></div></CardHeader><CardContent>{error && <div className="mb-4 rounded-xl bg-rose-50 p-3 text-sm text-rose-700 dark:bg-rose-950/30 dark:text-rose-300">{error}</div>}{jobs.length ? <div className="overflow-auto rounded-xl border border-slate-200 dark:border-slate-800"><table className="w-full min-w-[800px] text-left text-sm"><thead className="bg-slate-50 text-xs text-slate-500 dark:bg-slate-900"><tr><th className="p-3">任务</th><th className="p-3">词条</th><th className="p-3">模式</th><th className="p-3">状态</th><th className="p-3">尝试</th><th className="p-3">更新时间</th><th className="p-3">错误</th></tr></thead><tbody>{jobs.map((job) => <tr key={job.id} className="border-t border-slate-100 dark:border-slate-800"><td className="p-3 text-slate-400">#{job.id}</td><td className="p-3 font-medium"><Link href={`/words/${job.wordId}`} className="text-indigo-600 hover:underline dark:text-indigo-300">{job.term}</Link></td><td className="p-3 text-xs text-slate-500">{job.mode}</td><td className="p-3"><InitializationBadge status={job.status} /></td><td className="p-3">{job.attemptCount}/{job.maxAttempts}</td><td className="p-3 text-xs text-slate-500">{formatDate(job.updatedAt)}</td><td className="max-w-xs p-3 text-xs text-rose-500">{job.lastError ?? "—"}</td></tr>)}</tbody></table></div> : <EmptyState title="暂无初始化任务" description="导入 CSV 后，初始化任务会显示在这里。" />}</CardContent></Card>
  </div>;
}
