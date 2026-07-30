"use client";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { ArrowRight, BookOpen, Clock3, Loader2, Plus, Search, SlidersHorizontal, Upload } from "lucide-react";
import { apiFetch, formatDate } from "@/lib/client-api";
import { Badge, Button, Card, CardContent, Dialog, EmptyState, Input, PageHeader, Pagination, Select, buttonClass } from "@/components/ui";
import { InitializationBadge, MasteryBadge } from "@/components/status-badges";
import { LearningOverview } from "./learning-overview";

interface WordItem { id: number; term: string; sourceLanguage: string; targetLanguage: string; entryType: string; initializationStatus: string; masteryLevel: string; masteryScore: number; isSuspended: boolean; createdAt: string; dueAt: string | null; reps: number; wrongWordActive: boolean; definition: string | null; hasPronunciation: boolean; }
interface ResponseData { items: WordItem[]; pagination: { page: number; limit: number; total: number; pages: number } }

export default function WordsPage() {
  const [queryInput, setQueryInput] = useState("");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("");
  const [mastery, setMastery] = useState("");
  const [special, setSpecial] = useState("");
  const [sort, setSort] = useState("createdAt");
  const [page, setPage] = useState(1);
  const [data, setData] = useState<ResponseData | null>(null);
  const [error, setError] = useState("");
  const [filtersOpen, setFiltersOpen] = useState(false);

  useEffect(() => { const timer = window.setTimeout(() => { setQuery(queryInput.trim()); setPage(1); }, 350); return () => window.clearTimeout(timer); }, [queryInput]);
  const load = useCallback(async () => {
    const params = new URLSearchParams({ page: String(page), limit: "40", sort, order: sort === "term" ? "asc" : "desc" });
    if (query) params.set("q", query); if (status) params.set("status", status); if (mastery) params.set("mastery", mastery);
    if (special === "wrong") params.set("wrong", "true"); if (special === "due") params.set("due", "true"); if (special === "suspended") params.set("suspended", "true");
    try { setData(await apiFetch<ResponseData>(`/api/words?${params}`)); setError(""); }
    catch (reason) { setError(reason instanceof Error ? reason.message : "加载失败"); }
  }, [mastery, page, query, sort, special, status]);
  useEffect(() => { const timer = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(timer); }, [load]);

  const activeFilterCount = [status, mastery, special].filter(Boolean).length;
  const filters = <>
    <Select value={status} onChange={(event) => { setStatus(event.target.value); setPage(1); }}><option value="">全部初始化状态</option><option value="READY">已就绪</option><option value="PARTIAL">部分完成</option><option value="QUEUED">排队中</option><option value="RUNNING">初始化中</option><option value="FAILED">失败</option></Select>
    <Select value={mastery} onChange={(event) => { setMastery(event.target.value); setPage(1); }}><option value="">全部掌握状态</option><option value="NEW">新词</option><option value="LEARNING">学习中</option><option value="FAMILIAR">熟悉</option><option value="PROFICIENT">熟练</option><option value="MASTERED">已掌握</option></Select>
    <Select value={special} onChange={(event) => { setSpecial(event.target.value); setPage(1); }}><option value="">全部词条</option><option value="wrong">仅错词</option><option value="due">仅到期</option><option value="suspended">仅暂停</option></Select>
    <Select value={sort} onChange={(event) => { setSort(event.target.value); setPage(1); }}><option value="createdAt">按导入时间</option><option value="sourceCreatedAt">按收藏时间</option><option value="term">按字母</option><option value="masteryScore">按熟练度</option><option value="dueAt">按到期时间</option></Select>
  </>;
  function clearFilters() { setStatus(""); setMastery(""); setSpecial(""); setSort("createdAt"); setPage(1); }

  const hasPagination = Boolean(data && data.items.length > 0 && data.pagination.pages > 1);

  return <div className="space-y-4 sm:space-y-6"><PageHeader title="单词本" description="浏览词典内容、学习状态、错词和到期计划。" action={<div className="flex gap-2"><Link href="/create" className={buttonClass("primary")}><Plus className="size-4" />手动添加</Link><Link href="/import" className={`${buttonClass("outline")} hidden sm:inline-flex`}><Upload className="size-4" />导入 CSV</Link></div>} />
    <LearningOverview />
    <Card><CardContent className="pt-4 sm:pt-5"><div className="flex gap-2 sm:hidden"><div className="relative min-w-0 flex-1"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[#aeaeb2]" /><Input className="pl-9" placeholder="搜索词条或备注…" value={queryInput} onChange={(event) => setQueryInput(event.target.value)} /></div><Button variant="outline" onClick={() => setFiltersOpen(true)} aria-label="打开筛选"><SlidersHorizontal className="size-4" />{activeFilterCount ? activeFilterCount : "筛选"}</Button></div><div className="hidden gap-3 sm:grid sm:grid-cols-2 xl:grid-cols-[1fr_repeat(4,auto)]"><div className="relative"><Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[#aeaeb2]" /><Input className="pl-9" placeholder="搜索词条或备注…" value={queryInput} onChange={(event) => setQueryInput(event.target.value)} /></div>{filters}</div></CardContent></Card>
    <Dialog open={filtersOpen} onClose={() => setFiltersOpen(false)} title="筛选单词本"><div className="grid gap-3">{filters}<div className="mt-2 flex justify-between gap-2"><Button variant="ghost" onClick={clearFilters}>清除筛选</Button><Button onClick={() => setFiltersOpen(false)}>完成</Button></div></div></Dialog>
    {error && <div className="glass-inner rounded-[14px] border-[#ff3b30]/15 p-4 text-sm text-[#d70015] shadow-[0_8px_24px_rgba(255,59,48,0.08)] dark:text-[#ff453a]">{error}</div>}
    {!data && !error && <div className="grid min-h-64 place-items-center"><Loader2 className="size-8 animate-spin text-[#007aff]" /></div>}
    {data && data.items.length === 0 && <EmptyState icon={<BookOpen className="size-10 text-[#aeaeb2]" />} title="没有匹配的词条" description={query || status || mastery || special ? "调整筛选条件后再试。" : "先导入 EasyDict CSV，初始化完成后即可开始学习。"} action={!query && !status && !mastery && !special ? <Link href="/import" className={buttonClass("primary")}>导入 CSV</Link> : undefined} />}
    {data && data.items.length > 0 && <>{hasPagination && <Pagination sticky page={data.pagination.page} totalPages={Math.max(1, data.pagination.pages)} total={data.pagination.total} onChange={setPage} />}<div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3 2xl:grid-cols-4">{data.items.map((word) => <Link key={word.id} href={`/words/${word.id}`} className="group min-w-0"><Card className="ios-lift h-full min-h-[112px] sm:min-h-[128px]"><CardContent className="flex h-full items-start gap-3 pt-4 sm:gap-4 sm:pt-5"><div className="min-w-0 flex-1"><div className="flex flex-wrap items-center gap-2"><h2 className="truncate text-[16px] font-semibold tracking-tight transition-colors sm:text-[17px] group-hover:text-[#007aff] dark:group-hover:text-[#0a84ff]">{word.term}</h2>{word.wrongWordActive && <Badge tone="red">错词</Badge>}{word.isSuspended && <Badge>已暂停</Badge>}</div><p className="mt-1 truncate text-sm text-[#6e6e73] dark:text-[#98989d]">{word.definition ?? "暂无释义"}</p><div className="mt-2.5 flex flex-wrap items-center gap-2 sm:mt-3"><InitializationBadge status={word.initializationStatus} /><MasteryBadge level={word.masteryLevel} /><span className="text-xs text-[#aeaeb2] dark:text-[#48484a]">{word.sourceLanguage} → {word.targetLanguage}</span>{word.dueAt && <span className="inline-flex items-center gap-1 text-xs text-[#aeaeb2] dark:text-[#48484a]"><Clock3 className="size-3" />{formatDate(word.dueAt, { month: "numeric", day: "numeric" })}</span>}</div></div><div className="shrink-0 text-right"><p className="text-xl font-bold text-[#007aff] dark:text-[#0a84ff]">{word.masteryScore}</p><p className="text-[11px] text-[#aeaeb2] dark:text-[#48484a]">熟练度</p><ArrowRight className="ml-auto mt-3 size-4 text-[#c7c7cc] transition-transform group-hover:translate-x-1 dark:text-[#38383a]" /></div></CardContent></Card></Link>)}</div></>}
  </div>;
}
