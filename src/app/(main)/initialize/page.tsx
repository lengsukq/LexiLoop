"use client";
import { useCallback, useEffect, useState } from "react";
import { errorMessage } from "@/lib/format";
import { Loader2, Play, Plus, RefreshCw } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { toggleSetValue } from "@/lib/array";
import { BACKGROUND_TICK_EVENT } from "@/components/background-keepalive";
import { Button, Dialog, PageHeader, Pagination } from "@/components/ui";
import { InitializationConfigurator } from "./initialization-configurator";
import { InitializeProgress } from "./initialize-progress";
import { InitializeWordList } from "./initialize-word-list";
import { JobDetailDialog } from "./job-detail-dialog";
import type { InitializationWord, JobDetails, StatusData } from "./types";

const PAGE_SIZE = 50;

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

  const [detailJobId, setDetailJobId] = useState<number | null>(null);
  const [detailData, setDetailData] = useState<JobDetails | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState("");
  const [detailQueueing, setDetailQueueing] = useState(false);

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
    } catch (reason) { setError(errorMessage(reason, "加载失败")); }
  }, [filter, searchQuery, page]);

  // 数据刷新由全局 BackgroundKeepalive 的 tick 事件驱动（忙碌时约 3 秒一次、空闲 60 秒），
  // 不再自行轮询，避免与全局保活重复触发后台任务。
  useEffect(() => {
    const initial = window.setTimeout(() => void load(), 0);
    const onTick = () => void load();
    const onVisibilityChange = () => { if (!document.hidden) void load(); };
    window.addEventListener(BACKGROUND_TICK_EVENT, onTick);
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      window.clearTimeout(initial);
      window.removeEventListener(BACKGROUND_TICK_EVENT, onTick);
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE));

  async function runNow() {
    setRunning(true);
    setError("");
    setRunMessage("");
    try {
      const result = await apiFetch<{ claimed: number; elapsedMs: number }>("/api/initialization/run", { method: "POST" });
      setRunMessage(result.claimed > 0 ? `本轮已处理 ${result.claimed} 个任务（耗时 ${Math.round(result.elapsedMs / 1000)}s）` : "当前没有待处理的任务。");
      await load();
    } catch (reason) {
      setError(errorMessage(reason, "启动处理失败"));
    } finally {
      setRunning(false);
    }
  }

  async function retryWordIds(wordIds: number[]) {
    if (!wordIds.length) return;
    await apiFetch("/api/initialization/retry", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ wordIds }),
    });
    await load();
  }

  async function retryFailed() {
    setRetrying(true);
    try { await retryWordIds(words.filter((word) => word.failedTaskCount > 0).map((word) => word.wordId)); }
    catch (reason) { setError(errorMessage(reason, "重试失败")); }
    finally { setRetrying(false); }
  }

  async function retryWord(wordId: number) {
    setRetryingWordId(wordId);
    setError("");
    try { await retryWordIds([wordId]); }
    catch (reason) { setError(errorMessage(reason, "重试失败")); }
    finally { setRetryingWordId(null); }
  }

  function toggleSelectAllVisible(checked: boolean) {
    setSelectedWordIds((current) => {
      const next = new Set(current);
      for (const word of words) {
        if (checked) next.add(word.wordId);
        else next.delete(word.wordId);
      }
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
      setDetailError(errorMessage(reason, "加载任务详情失败"));
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
    } catch (reason) { setDetailError(errorMessage(reason, "创建补全任务失败")); }
    finally { setDetailQueueing(false); }
  }

  return (
    <div className="space-y-5 pb-20 sm:pb-4">
      <PageHeader
        title="词条初始化"
        description="为词条补齐释义、音标、例句等学习内容；选择范围后创建后台任务。"
        action={
          <div className="flex items-center gap-2">
            <Button variant="outline" onClick={() => void load()}><RefreshCw className="size-4" />刷新</Button>
            <Button variant="outline" onClick={() => void runNow()} disabled={running}>
              {running ? <Loader2 className="size-4 animate-spin" /> : <Play className="size-4" />}{running ? "处理中..." : "立即处理"}
            </Button>
            <Button onClick={() => openConfigurator()}><Plus className="size-4" />创建任务</Button>
          </div>
        }
      />
      {status && (
        <InitializeProgress
          status={status}
          hasFailedWords={words.some((word) => word.failedTaskCount > 0)}
          runMessage={runMessage}
          retrying={retrying}
          onRetryFailed={() => void retryFailed()}
        />
      )}
      {words.length > 0 && <Pagination sticky page={page} totalPages={totalPages} total={totalCount} onChange={setPage} />}
      <InitializeWordList
        words={words}
        error={error}
        searchQuery={searchQuery}
        filter={filter}
        selectedWordIds={selectedWordIds}
        expandedWordIds={expandedWordIds}
        retryingWordId={retryingWordId}
        onSearchChange={(value) => { setSearchQuery(value); setPage(1); }}
        onFilterChange={(value) => { setFilter(value); setPage(1); }}
        onToggleSelect={(wordId) => setSelectedWordIds((current) => toggleSetValue(current, wordId))}
        onToggleAllVisible={toggleSelectAllVisible}
        onToggleExpand={(wordId) => setExpandedWordIds((current) => toggleSetValue(current, wordId))}
        onRetryWord={(wordId) => void retryWord(wordId)}
        onOpenDetail={(taskId) => void openDetail(taskId)}
        onClearSelection={() => setSelectedWordIds(new Set())}
        onConfigureSelected={() => openConfigurator("SELECTED")}
      />
      <Dialog open={configuratorOpen} onClose={() => setConfiguratorOpen(false)} title="配置初始化" maxWidth="max-w-4xl">
        <InitializationConfigurator selectedWordIds={selectedWordIds} setSelectedWordIds={setSelectedWordIds} onQueued={load} requestedScope={configuratorScope} />
      </Dialog>
      <JobDetailDialog
        jobId={detailJobId}
        data={detailData}
        loading={detailLoading}
        error={detailError}
        queueing={detailQueueing}
        onClose={() => setDetailJobId(null)}
        onQueueWord={() => void queueDetailWord()}
      />
    </div>
  );
}
