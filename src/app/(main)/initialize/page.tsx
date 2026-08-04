"use client";
import Link from "next/link";
import { Fragment, useCallback, useEffect, useMemo, useState } from "react";
import { AlertCircle, ChevronDown, ChevronRight, Clock3, ExternalLink, Loader2, Play, Plus, RefreshCw, RotateCcw, Sparkles, XCircle } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Dialog, EmptyState, PageHeader, Pagination, Progress } from "@/components/ui";
import { InitializationBadge } from "@/components/status-badges";
import { InitializationConfigurator } from "./initialization-configurator";

interface StatusData { summary: Record<string, number>; wordSummary: Record<string, number>; }
interface InitializationTask {
  id: number;
  taskType: string;
  status: string;
  mode: string;
  attemptCount: number;
  maxAttempts: number;
  lastError: string | null;
  lastErrorCode: string | null;
  createdAt: number;
  updatedAt: number;
  completedAt: number | null;
}

interface InitializationWord {
  wordId: number;
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  status: string;
  taskCount: number;
  completedTaskCount: number;
  failedTaskCount: number;
  activeTaskCount: number;
  updatedAt: number;
  errorSummary: string | null;
  tasks: InitializationTask[];
}

interface JobAttempt {
  id: number;
  providerId: string;
  status: string;
  durationMs: number;
  fieldsReturned: string[];
  errorCode: string | null;
  errorMessage: string | null;
  metadata: {
    model?: string;
    promptVersion?: string;
    schemaVersion?: number;
    inputTokens?: number | null;
    outputTokens?: number | null;
    qualityScore?: number;
    finishReason?: string | null;
  } | null;
  createdAt: number;
}

interface JobDetails {
  job: {
    id: number;
    wordId: number;
    term: string;
    normalizedTerm: string;
    sourceLanguage: string;
    targetLanguage: string;
    taskType: string;
    status: string;
    mode: string;
    priority: number;
    attemptCount: number;
    maxAttempts: number;
    lastError: string | null;
    lastErrorCode: string | null;
    availableAt: number | null;
    lockedAt: number | null;
    lockedBy: string | null;
    createdAt: number;
    updatedAt: number;
    completedAt: number | null;
  };
  attempts: JobAttempt[];
  contentFields: Record<string, boolean>;
}

const MODE_LABELS: Record<string, string> = {
  SKIP_INITIALIZED: "跳过已初始化",
  FILL_MISSING_FIELDS: "补全缺失字段",
  FORCE_OVERWRITE: "强制覆盖",
};
const TASK_TYPE_LABELS: Record<string, string> = { INITIALIZE: "词条补全", MNEMONIC: "中文助记", EXAMPLE_TRANSLATIONS: "翻译补全" };

function formatTs(ts: number | string | null | undefined): string {
  if (!ts) return "—";
  const d = typeof ts === "number" ? new Date(ts) : new Date(ts);
  return d.toLocaleString("zh-CN");
}

function durationText(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(1)}s`;
  return `${Math.floor(ms / 60000)}m ${Math.floor((ms % 60000) / 1000)}s`;
}

const CONTENT_FIELD_LABELS: Record<string, string> = {
  definitions: "释义",
  pronunciations: "发音",
  examples: "例句",
  phrases: "搭配",
  forms: "词形",
  synonyms: "近义词",
  antonyms: "反义词",
  wordFamily: "同根词",
  confusedWords: "易混词",
  roots: "词根",
  affixes: "词缀",
  tags: "标签",
  summary: "概要",
  learning: "学习提示",
  sentenceAnalysis: "句子分析",
};

function contentFieldLabel(key: string): string {
  return CONTENT_FIELD_LABELS[key] ?? key;
}

export default function InitializePage() {
  const [status, setStatus] = useState<StatusData | null>(null);
  const [words, setWords] = useState<InitializationWord[]>([]);
  const [totalCount, setTotalCount] = useState(0);
  const [filter, setFilter] = useState("");
  const [searchQuery, setSearchQuery] = useState("");
  const [page, setPage] = useState(1);
  const [error, setError] = useState("");
  const [retrying, setRetrying] = useState(false);
  const [running, setRunning] = useState(false);
  const [runMessage, setRunMessage] = useState("");
  const [retryingWordId, setRetryingWordId] = useState<number | null>(null);
  const [selectedWordIds, setSelectedWordIds] = useState<Set<number>>(new Set());
  const [configuratorOpen, setConfiguratorOpen] = useState(false);
  const [configuratorScope, setConfiguratorScope] = useState<"ALL" | "SELECTED">("ALL");
  const [expandedWordIds, setExpandedWordIds] = useState<Set<number>>(new Set());

  // Dialog state
  const [detailJobId, setDetailJobId] = useState<number | null>(null);
  const [detailData, setDetailData] = useState<JobDetails | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState("");
  const [detailQueueing, setDetailQueueing] = useState(false);

  const PAGE_SIZE = 50;

  const load = useCallback(async () => {
    try {
      const params = new URLSearchParams();
      if (filter) params.set("status", filter);
      if (searchQuery) params.set("search", searchQuery);
      params.set("page", String(page));
      params.set("pageSize", String(PAGE_SIZE));
      const [statusData, jobData] = await Promise.all([
        apiFetch<StatusData>("/api/initialization/status"),
        apiFetch<{ items: InitializationWord[]; total: number }>(`/api/initialization?${params}`),
      ]);
      setStatus(statusData);
      setWords(jobData.items);
      setTotalCount(jobData.total);
      setError("");
    } catch (reason) { setError(reason instanceof Error ? reason.message : "加载失败"); }
  }, [filter, searchQuery, page]);

  useEffect(() => {
    const initial = window.setTimeout(() => void load(), 0);
    const timer = window.setInterval(() => void load(), 3000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  }, [load]);

  const wordTotal = useMemo(() => status ? Object.values(status.wordSummary).reduce((sum, value) => sum + value, 0) : 0, [status]);
  const wordCompleted = (status?.wordSummary.READY ?? 0) + (status?.wordSummary.PARTIAL ?? 0);
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  function handleFilterChange(value: string) {
    setFilter(value);
    setPage(1);
  }

  function handleSearchChange(value: string) {
    setSearchQuery(value);
    setPage(1);
  }

  async function runNow() {
    setRunning(true);
    setError("");
    setRunMessage("");
    try {
      const result = await apiFetch<{ claimed: number; elapsedMs: number }>("/api/initialization/run", { method: "POST" });
      setRunMessage(result.claimed > 0 ? `本轮已处理 ${result.claimed} 个任务（耗时 ${Math.round(result.elapsedMs / 1000)}s）` : "当前没有待处理的任务。");
      await load();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "启动处理失败");
    } finally {
      setRunning(false);
    }
  }
  async function retryFailed() {
    const wordIds = words.filter((word) => word.failedTaskCount > 0).map((word) => word.wordId);
    if (!wordIds.length) return;
    setRetrying(true);
    try { await apiFetch("/api/initialization/retry", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ wordIds }) }); await load(); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "重试失败"); }
    finally { setRetrying(false); }
  }
  async function retryWord(wordId: number) {
    setRetryingWordId(wordId);
    setError("");
    try {
      await apiFetch("/api/initialization/retry", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ wordIds: [wordId] }),
      });
      await load();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "重试失败");
    } finally {
      setRetryingWordId(null);
    }
  }
  function toggleWordSelection(wordId: number) {
    setSelectedWordIds((current) => {
      const next = new Set(current);
      if (next.has(wordId)) next.delete(wordId);
      else next.add(wordId);
      return next;
    });
  }

  function selectVisibleWords() {
    setSelectedWordIds((current) => {
      const next = new Set(current);
      for (const word of words) next.add(word.wordId);
      return next;
    });
  }

  function toggleWordExpansion(wordId: number) {
    setExpandedWordIds((current) => {
      const next = new Set(current);
      if (next.has(wordId)) next.delete(wordId);
      else next.add(wordId);
      return next;
    });
  }

  function openConfigurator(scope: "ALL" | "SELECTED" = selectedWordIds.size ? "SELECTED" : "ALL") {
    setConfiguratorScope(scope);
    setConfiguratorOpen(true);
  }

  async function openDetail(jobId: number) {
    setDetailJobId(jobId);
    setDetailData(null);
    setDetailLoading(true);
    setDetailError("");
    try {
      setDetailData(await apiFetch<JobDetails>(`/api/initialization/${jobId}`));
    } catch (reason) {
      setDetailError(reason instanceof Error ? reason.message : "加载任务详情失败");
    } finally {
      setDetailLoading(false);
    }
  }

  async function queueDetailWord() {
    if (!detailData) return;
    setDetailQueueing(true);
    setDetailError("");
    try {
      await apiFetch(`/api/words/${detailData.job.wordId}/initialize`, {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode: "FILL_MISSING_FIELDS" }),
      });
      await Promise.all([load(), openDetail(detailData.job.id)]);
    } catch (reason) { setDetailError(reason instanceof Error ? reason.message : "创建补全任务失败"); }
    finally { setDetailQueueing(false); }
  }

  return <div className="space-y-5 pb-20 sm:pb-4"><PageHeader title="词条初始化" description="为词条补齐释义、音标、例句等学习内容；选择范围后创建后台任务。" action={<div className="flex items-center gap-2"><Button variant="outline" onClick={() => void load()}><RefreshCw className="size-4" />刷新</Button><Button variant="outline" onClick={() => void runNow()} disabled={running}>{running ? <Loader2 className="size-4 animate-spin" /> : <Play className="size-4" />}{running ? "处理中..." : "立即处理"}</Button><Button onClick={() => openConfigurator()}><Plus className="size-4" />创建任务</Button></div>} />
    {status && <Card>
      <CardContent className="pt-5">
        <div className="grid gap-5 lg:grid-cols-[minmax(240px,0.9fr)_minmax(0,1.4fr)] lg:items-center">
          <div>
            <div className="flex items-end justify-between gap-3">
              <div><p className="text-sm font-semibold">词条初始化进度</p><p className="mt-1 text-xs text-[#8e8e93]">已完成 {wordCompleted} / {wordTotal}</p></div>
              <b className="text-2xl tracking-tight">{wordTotal ? Math.round(wordCompleted / wordTotal * 100) : 0}%</b>
            </div>
            <Progress value={wordCompleted} max={Math.max(1, wordTotal)} className="mt-3" />
          </div>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {[
              { label: "排队", value: status.summary.QUEUED ?? 0, icon: Clock3, className: "text-[#007aff] bg-[#007aff]/10" },
              { label: "处理中", value: status.summary.RUNNING ?? 0, icon: Loader2, className: "text-[#5856d6] bg-[#5856d6]/10" },
              { label: "部分完成", value: status.summary.PARTIAL ?? 0, icon: AlertCircle, className: "text-[#ff9500] bg-[#ff9500]/10" },
              { label: "失败", value: status.summary.FAILED ?? 0, icon: XCircle, className: "text-[#ff3b30] bg-[#ff3b30]/10" },
            ].map((item) => <div key={item.label} className="flex items-center gap-3 rounded-[14px] bg-black/[0.025] p-3 dark:bg-white/[0.035]"><span className={`grid size-9 shrink-0 place-items-center rounded-[11px] ${item.className}`}><item.icon className={`size-4 ${item.label === "处理中" && item.value > 0 ? "animate-spin" : ""}`} /></span><div><b className="block text-lg leading-none">{item.value}</b><span className="mt-1 block text-xs text-[#8e8e93]">{item.label}</span></div></div>)}
          </div>
        </div>
        {runMessage && <p className="mt-3 text-xs text-[#007aff] dark:text-[#0a84ff]">{runMessage}</p>}
        {words.some((word) => word.failedTaskCount > 0) && <Button className="mt-4" variant="outline" size="sm" onClick={() => void retryFailed()} disabled={retrying}>{retrying ? <Loader2 className="size-4 animate-spin" /> : <RotateCcw className="size-4" />}重试当前失败词条</Button>}
      </CardContent>
    </Card>}
    {words.length > 0 && <Pagination sticky page={page} totalPages={totalPages} total={totalCount} onChange={setPage} />}
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <CardTitle>按词条查看记录</CardTitle>
            <p className="mt-1 text-xs text-[#aeaeb2]">每个词条只占一行，展开后查看具体初始化子任务。</p>
          </div>
          <div className="flex w-full items-center gap-2 sm:w-auto">
            <input
              className="h-9 min-w-0 flex-1 rounded-[14px] border border-black/[0.06] bg-white/60 px-3 text-sm shadow-[inset_0_1px_3px_rgba(0,0,0,0.03)] outline-none backdrop-blur-sm transition placeholder:text-[#aeaeb2] focus:border-[#007aff]/40 focus:shadow-[0_0_0_4px_rgba(0,122,255,0.08)] sm:w-48 sm:flex-none dark:border-white/[0.08] dark:bg-white/[0.04]"
              placeholder="搜索词条..."
              value={searchQuery}
              onChange={(event) => handleSearchChange(event.target.value)}
            />
            <select
              className="h-9 w-[108px] shrink-0 rounded-[14px] border border-black/[0.06] bg-white/60 px-3 text-sm shadow-[0_2px_8px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.08] dark:bg-white/[0.04]"
              value={filter}
              onChange={(event) => handleFilterChange(event.target.value)}
            >
              <option value="">全部状态</option>
              <option value="QUEUED">排队</option>
              <option value="RUNNING">处理中</option>
              <option value="READY">就绪</option>
              <option value="PARTIAL">部分完成</option>
              <option value="FAILED">失败</option>
            </select>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {error && <div className="mb-4 rounded-[16px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.06] p-3 text-sm text-[#d70015] shadow-[0_4px_16px_rgba(255,59,48,0.05)] backdrop-blur-sm dark:text-[#ff453a]">{error}</div>}
        {selectedWordIds.size > 0 && <div className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-[16px] border border-[#007aff]/15 bg-[#007aff]/[0.06] p-3 text-sm text-[#005ecb] dark:text-[#64b5ff]">
          <span>已选 {selectedWordIds.size} 个词条。配置初始化会为它们补齐释义、音标、例句等内容。</span>
          <div className="flex gap-2">
            <Button variant="ghost" size="sm" onClick={() => setSelectedWordIds(new Set())}>取消选择</Button>
            <Button size="sm" onClick={() => openConfigurator("SELECTED")}>配置初始化</Button>
          </div>
        </div>}
        {words.length ? <>
          <div className="space-y-2.5 sm:hidden">
            <div className="flex items-center justify-between rounded-[14px] bg-black/[0.025] px-3 py-2 text-xs text-[#6e6e73] dark:bg-white/[0.04] dark:text-[#98989d]">
              <label className="flex cursor-pointer items-center gap-2.5">
                <input type="checkbox" className="size-4 accent-[#007aff]" aria-label="选择当前页全部词条" checked={words.length > 0 && words.every((word) => selectedWordIds.has(word.wordId))} onChange={(event) => {
                  if (event.target.checked) selectVisibleWords();
                  else setSelectedWordIds((current) => {
                    const next = new Set(current);
                    for (const word of words) next.delete(word.wordId);
                    return next;
                  });
                }} />
                <span>选择当前页</span>
              </label>
              <span>{words.length} 条词条</span>
            </div>
            {words.map((word) => {
              const expanded = expandedWordIds.has(word.wordId);
              const completionPercent = word.taskCount ? Math.round(word.completedTaskCount / word.taskCount * 100) : 0;
              return <div key={word.wordId} className="glass-inner rounded-[18px] p-3.5">
                <div className="flex items-start gap-2.5">
                  <label className="grid size-9 shrink-0 cursor-pointer place-items-center rounded-[11px] bg-black/[0.025] dark:bg-white/[0.05]" onClick={(event) => event.stopPropagation()}>
                    <input type="checkbox" className="size-4 accent-[#007aff]" aria-label={`选择 ${word.term}`} checked={selectedWordIds.has(word.wordId)} onChange={() => toggleWordSelection(word.wordId)} />
                  </label>
                  <div className="min-w-0 flex-1">
                    <div className="flex min-w-0 items-center gap-2">
                      <button type="button" className="grid size-7 shrink-0 place-items-center rounded-[9px] bg-[#007aff]/[0.08] text-[#007aff] dark:text-[#0a84ff]" onClick={() => toggleWordExpansion(word.wordId)} aria-label={expanded ? `收起 ${word.term}` : `展开 ${word.term}`}>{expanded ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}</button>
                      <Link href={`/words/${word.wordId}`} className="flex min-w-0 items-center gap-1 truncate font-semibold text-[#007aff] dark:text-[#0a84ff]" onClick={(event) => event.stopPropagation()}>{word.term}<ExternalLink className="size-3 shrink-0" /></Link>
                    </div>
                    <span className="mt-1.5 block text-xs text-[#8e8e93]">{word.completedTaskCount}/{word.taskCount} 已完成{word.activeTaskCount > 0 ? ` · ${word.activeTaskCount} 个处理中` : ""}</span>
                  </div>
                  <InitializationBadge status={word.status} />
                </div>
                <div className="mt-3 pl-[3.25rem]">
                  <div className="flex items-center justify-between gap-2 text-[11px] text-[#8e8e93]"><span>初始化进度</span><span>{completionPercent}%</span></div>
                  <Progress value={word.completedTaskCount} max={Math.max(1, word.taskCount)} className="mt-1.5 h-1.5" />
                  <div className="mt-2 flex items-center justify-between gap-2">
                    <span className="truncate text-[11px] text-[#aeaeb2]">{word.errorSummary ?? `更新时间：${formatTs(word.updatedAt)}`}</span>
                    {word.failedTaskCount > 0 && <Button variant="outline" size="sm" className="h-8 shrink-0 px-2.5 text-xs" onClick={() => void retryWord(word.wordId)} disabled={retryingWordId !== null}>
                      {retryingWordId === word.wordId ? <Loader2 className="size-3.5 animate-spin" /> : <RotateCcw className="size-3.5" />}重试
                    </Button>}
                  </div>
                </div>
                {expanded && <div className="mt-3 space-y-2 border-t border-black/[0.05] pt-3 dark:border-white/[0.08]">
                  {word.tasks.map((task) => <button key={task.id} type="button" className="block w-full rounded-[13px] border border-white/60 bg-white/55 p-2.5 text-left shadow-[0_3px_12px_rgba(0,0,0,0.03)] transition hover:bg-white/75 dark:border-white/[0.07] dark:bg-white/[0.04] dark:hover:bg-white/[0.07]" onClick={() => void openDetail(task.id)}>
                    <div className="flex flex-wrap items-center justify-between gap-2"><span className="flex items-center gap-2 text-xs font-medium">{TASK_TYPE_LABELS[task.taskType] ?? task.taskType}<InitializationBadge status={task.status} /></span><span className="text-[11px] text-[#8e8e93]">任务 #{task.id}</span></div>
                    <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-[11px] text-[#6e6e73] dark:text-[#98989d]"><span>重试 {task.attemptCount}/{task.maxAttempts}</span><span>更新：{formatTs(task.updatedAt)}</span></div>
                  </button>)}
                </div>}
              </div>;
            })}
          </div>
          <div className="hidden overflow-auto rounded-[18px] border border-white/50 shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-sm dark:border-white/[0.08] sm:block">
            <table className="w-full min-w-[840px] text-left text-sm">
              <thead className="bg-black/[0.03] text-xs text-[#6e6e73] dark:bg-white/[0.04] dark:text-[#98989d]">
                <tr>
                  <th className="w-10 p-3"><label className="grid size-10 cursor-pointer place-items-center"><input type="checkbox" className="size-4.5 accent-[#007aff]" aria-label="选择当前页全部词条" checked={words.length > 0 && words.every((word) => selectedWordIds.has(word.wordId))} onChange={(event) => {
                    if (event.target.checked) selectVisibleWords();
                    else setSelectedWordIds((current) => {
                      const next = new Set(current);
                      for (const word of words) next.delete(word.wordId);
                      return next;
                    });
                  }} /></label></th>
                  <th className="min-w-[160px] p-3">词条</th>
                  <th className="whitespace-nowrap p-3">状态</th>
                  <th className="min-w-[180px] p-3">错误</th>
                  <th className="w-24 p-3">操作</th>
                </tr>
              </thead>
              <tbody>
                {words.map((word) => {
                  const expanded = expandedWordIds.has(word.wordId);
                  return <Fragment key={word.wordId}>
                    <tr
                      className="cursor-pointer border-t border-black/[0.04] transition hover:bg-black/[0.02] dark:border-white/[0.06] dark:hover:bg-white/[0.03]"
                      onClick={() => toggleWordExpansion(word.wordId)}
                    >
                      <td className="p-3" onClick={(event) => event.stopPropagation()}>
                        <label className="grid size-10 cursor-pointer place-items-center"><input type="checkbox" className="size-4.5 accent-[#007aff]" aria-label={`选择 ${word.term}`} checked={selectedWordIds.has(word.wordId)} onChange={() => toggleWordSelection(word.wordId)} /></label>
                      </td>
                      <td className="p-3 font-medium">
                        <div className="flex items-center gap-2">
                          <span className="grid size-7 shrink-0 place-items-center rounded-[10px] bg-[#007aff]/[0.08] text-[#007aff] dark:text-[#0a84ff]">
                            {expanded ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
                          </span>
                          <Link href={`/words/${word.wordId}`} className="text-[#007aff] hover:underline dark:text-[#0a84ff]" onClick={(event) => event.stopPropagation()}>
                            <span className="inline-flex items-center gap-1">{word.term}<ExternalLink className="size-3" /></span>
                          </Link>
                        </div>
                        <div className="mt-1 pl-9 text-xs font-normal text-[#8e8e93]">
                          <span className="font-medium">{word.completedTaskCount}/{word.taskCount}</span>
                          <span className="ml-1">已完成</span>
                          {word.activeTaskCount > 0 && <span className="ml-2 text-[#007aff]">· {word.activeTaskCount} 个处理中</span>}
                        </div>
                      </td>
                      <td className="whitespace-nowrap p-3">
                        <div><InitializationBadge status={word.status} /></div>
                        <div className="mt-1 text-xs text-[#6e6e73] dark:text-[#98989d]">{formatTs(word.updatedAt)}</div>
                      </td>
                      <td className="max-w-xs truncate p-3 text-xs text-[#ff3b30]">{word.errorSummary ?? (word.failedTaskCount ? `有 ${word.failedTaskCount} 个失败子任务` : "—")}</td>
                      <td className="p-3">
                        {word.failedTaskCount > 0 && <Button variant="outline" size="sm" onClick={(event) => {
                          event.stopPropagation();
                          void retryWord(word.wordId);
                        }} disabled={retryingWordId !== null}>
                          {retryingWordId === word.wordId ? <Loader2 className="size-4 animate-spin" /> : <RotateCcw className="size-4" />}重试
                        </Button>}
                      </td>
                    </tr>
                    {expanded && <tr className="border-t border-black/[0.03] bg-[#007aff]/[0.025] dark:border-white/[0.04] dark:bg-white/[0.02]">
                      <td colSpan={5} className="px-5 py-3">
                        <div className="space-y-2 pl-9">
                          {word.tasks.map((task) => <button key={task.id} type="button" className="block w-full rounded-[14px] border border-white/60 bg-white/55 p-3 text-left shadow-[0_3px_12px_rgba(0,0,0,0.03)] transition hover:border-[#007aff]/25 hover:bg-white/75 dark:border-white/[0.07] dark:bg-white/[0.04] dark:hover:bg-white/[0.07]" onClick={() => void openDetail(task.id)}>
                            <div className="flex flex-wrap items-center justify-between gap-2">
                              <div className="flex items-center gap-2">
                                <span className="font-medium">{TASK_TYPE_LABELS[task.taskType] ?? task.taskType}</span>
                                <InitializationBadge status={task.status} />
                              </div>
                              <span className="text-xs text-[#8e8e93]">任务 #{task.id}</span>
                            </div>
                            <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-xs text-[#6e6e73] dark:text-[#98989d]">
                              <span>重试 {task.attemptCount}/{task.maxAttempts}</span>
                              <span>更新时间：{formatTs(task.updatedAt)}</span>
                              {task.lastError && <span className="max-w-full truncate text-[#ff3b30]">{task.lastError}</span>}
                            </div>
                          </button>)}
                        </div>
                      </td>
                    </tr>}
                  </Fragment>;
                })}
              </tbody>
            </table>
          </div>
        </> : <EmptyState title="暂无初始化任务" description="导入 CSV 后，初始化任务会显示在这里。" />}
      </CardContent>
    </Card>
    <Dialog open={configuratorOpen} onClose={() => setConfiguratorOpen(false)} title="配置初始化" maxWidth="max-w-4xl">
          <InitializationConfigurator selectedWordIds={selectedWordIds} setSelectedWordIds={setSelectedWordIds} onQueued={load} requestedScope={configuratorScope} />
        </Dialog>

    <Dialog open={detailJobId !== null} onClose={() => setDetailJobId(null)} title={detailData ? `任务 #${detailData.job.id} 详情` : "任务详情"}>
      {detailLoading && <div className="flex items-center justify-center py-8"><Loader2 className="size-6 animate-spin text-[#007aff]" /></div>}
      {detailError && <div className="rounded-[16px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.06] p-3 text-sm text-[#d70015] shadow-[0_4px_16px_rgba(255,59,48,0.05)] backdrop-blur-sm dark:text-[#ff453a]">{detailError}</div>}
      {detailData && <>
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div>
              <span className="text-[#aeaeb2]">状态</span>
              <p className="mt-0.5"><InitializationBadge status={detailData.job.status} /></p>
            </div>
            <div>
              <span className="text-[#aeaeb2]">词条</span>
              <p className="mt-0.5 font-medium">
                <Link href={`/words/${detailData.job.wordId}`} className="text-[#007aff] hover:underline dark:text-[#0a84ff]" onClick={() => setDetailJobId(null)}>
                  {detailData.job.term}
                </Link>
              </p>
            </div>
            <div>
              <span className="text-[#aeaeb2]">模式</span>
              <p className="mt-0.5">{MODE_LABELS[detailData.job.mode] ?? detailData.job.mode}</p>
            </div>
            <div>
              <span className="text-[#aeaeb2]">任务类型</span>
              <p className="mt-0.5">{TASK_TYPE_LABELS[detailData.job.taskType] ?? detailData.job.taskType}</p>
            </div>
            <div>
              <span className="text-[#aeaeb2]">重试</span>
              <p className="mt-0.5">{detailData.job.attemptCount}/{detailData.job.maxAttempts}</p>
            </div>
            <div className="col-span-2">
              <span className="text-[#aeaeb2]">更新时间</span>
              <p className="mt-0.5">{formatTs(detailData.job.updatedAt)}</p>
            </div>
            {detailData.job.lastError && (
              <div className="col-span-2">
                <span className="text-[#aeaeb2]">错误信息</span>
                <p className="mt-0.5 whitespace-pre-wrap rounded-[12px] border border-[#ff3b30]/10 bg-[#ff3b30]/[0.05] p-2 text-xs text-[#ff3b30] backdrop-blur-sm">
                  {detailData.job.lastError}
                  {detailData.job.lastErrorCode && <span className="ml-2 font-mono opacity-60">({detailData.job.lastErrorCode})</span>}
                </p>
              </div>
            )}
          </div>

          <div className="rounded-[16px] border border-[#007aff]/10 bg-[#007aff]/[0.04] p-3">
            <p className="text-xs leading-5 text-[#6e6e73] dark:text-[#98989d]">此操作会为「{detailData.job.term}」补全缺失的释义、例句、助记等内容；手动编辑的释义和例句会保留。</p>
            <Button className="mt-3" size="sm" onClick={() => void queueDetailWord()} disabled={detailQueueing}>{detailQueueing ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}补全这个词</Button>
          </div>

          {detailData.contentFields && <>
            <hr className="border-black/[0.06] dark:border-white/[0.08]" />
            <h3 className="text-sm font-medium">已获取内容字段</h3>
            <div className="flex flex-wrap gap-2 text-xs">
              {Object.entries(detailData.contentFields).map(([key, present]) => (
                <span key={key} className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 shadow-[0_2px_6px_rgba(0,0,0,0.03)] backdrop-blur-sm ${
                  present
                    ? "border border-[#34c759]/15 bg-[#34c759]/[0.08] text-[#248a3d] dark:text-[#30d158]"
                    : "border border-black/[0.04] bg-black/[0.03] text-[#aeaeb2] dark:border-white/[0.06] dark:bg-white/[0.04]"
                }`}>
                  {present ? "✓" : "○"} {contentFieldLabel(key)}
                </span>
              ))}
            </div>
          </>}

          {detailData.attempts.length > 0 && <>
            <hr className="border-black/[0.06] dark:border-white/[0.08]" />
            <h3 className="text-sm font-medium">Provider 调用</h3>
            <div className="space-y-2 max-h-48 overflow-y-auto">
              {detailData.attempts.map((attempt) => (
                <div key={attempt.id} className="rounded-[14px] border border-white/50 bg-white/40 p-3 text-xs shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{attempt.providerId}</span>
                    <Badge tone={attempt.status === "SUCCESS" ? "green" : attempt.status === "EMPTY" ? "amber" : "red"}>{attempt.status}</Badge>
                  </div>
                  <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-[#6e6e73] dark:text-[#98989d]">
                    <span>耗时：{durationText(attempt.durationMs)}</span>
                    {attempt.metadata?.model && <span>模型：{attempt.metadata.model}</span>}
                    {attempt.metadata?.qualityScore != null && <span>评分：{attempt.metadata.qualityScore}</span>}
                    {attempt.fieldsReturned.length > 0 && <span>字段：{attempt.fieldsReturned.join("、")}</span>}
                  </div>
                  {attempt.errorMessage && <p className="mt-1 text-[#ff3b30]">{attempt.errorMessage}</p>}
                </div>
              ))}
            </div>
          </>}
        </div>
      </>}
    </Dialog>
  </div>;
}
