import Link from "next/link";
import { ChevronDown, ChevronRight, ExternalLink, Loader2, RotateCcw } from "lucide-react";
import { Alert, Button, Card, CardContent, CardHeader, CardTitle, EmptyState, Progress, SearchInput, Select } from "@/components/ui";
import { InitializationBadge } from "@/components/status-badges";
import { TASK_TYPE_LABELS, formatTs, type InitializationTask, type InitializationWord } from "./types";

const FILTER_OPTIONS = [
  { value: "", label: "全部状态" },
  { value: "QUEUED", label: "排队" },
  { value: "RUNNING", label: "处理中" },
  { value: "READY", label: "就绪" },
  { value: "PARTIAL", label: "部分完成" },
  { value: "FAILED", label: "失败" },
];

export function InitializeWordList({
  words, error, searchQuery, filter,
  selectedWordIds, expandedWordIds, retryingWordId,
  onSearchChange, onFilterChange,
  onToggleSelect, onToggleAllVisible, onToggleExpand,
  onRetryWord, onOpenDetail,
  onClearSelection, onConfigureSelected,
}: {
  words: InitializationWord[];
  error: string;
  searchQuery: string;
  filter: string;
  selectedWordIds: Set<number>;
  expandedWordIds: Set<number>;
  retryingWordId: number | null;
  onSearchChange: (value: string) => void;
  onFilterChange: (value: string) => void;
  onToggleSelect: (wordId: number) => void;
  onToggleAllVisible: (checked: boolean) => void;
  onToggleExpand: (wordId: number) => void;
  onRetryWord: (wordId: number) => void;
  onOpenDetail: (taskId: number) => void;
  onClearSelection: () => void;
  onConfigureSelected: () => void;
}) {
  const allVisibleSelected = words.length > 0 && words.every((word) => selectedWordIds.has(word.wordId));

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <CardTitle>按词条查看记录</CardTitle>
            <p className="mt-1 text-xs text-tertiary-label">每个词条只占一行，展开后查看具体初始化子任务。</p>
          </div>
          <div className="flex w-full items-center gap-2 sm:w-auto">
            <SearchInput
              className="min-w-0 flex-1 sm:w-48 sm:flex-none"
              placeholder="搜索词条..."
              value={searchQuery}
              onChange={(event) => onSearchChange(event.target.value)}
            />
            <Select
              compact
              className="w-[108px] shrink-0"
              aria-label="按状态筛选"
              value={filter}
              onChange={(event) => onFilterChange(event.target.value)}
            >
              {FILTER_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
            </Select>
          </div>
        </div>
      </CardHeader>
      <CardContent>
        {error && <Alert className="mb-4">{error}</Alert>}
        {selectedWordIds.size > 0 && (
          <Alert tone="info" className="mb-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <span>已选 {selectedWordIds.size} 个词条。配置初始化会为它们补齐释义、音标、例句等内容。</span>
              <div className="flex gap-2">
                <Button variant="ghost" size="sm" onClick={onClearSelection}>取消选择</Button>
                <Button size="sm" onClick={onConfigureSelected}>配置初始化</Button>
              </div>
            </div>
          </Alert>
        )}
        {words.length ? <>
          {/* 移动端卡片视图 */}
          <div className="space-y-2.5 sm:hidden">
            <div className="flex items-center justify-between rounded-[14px] bg-black/[0.025] px-3 py-2 text-xs text-secondary-label dark:bg-white/[0.04]">
              <label className="flex cursor-pointer items-center gap-2.5">
                <input type="checkbox" className="size-4 accent-accent" aria-label="选择当前页全部词条" checked={allVisibleSelected} onChange={(event) => onToggleAllVisible(event.target.checked)} />
                <span>选择当前页</span>
              </label>
              <span>{words.length} 条词条</span>
            </div>
            {words.map((word) => (
              <MobileWordCard
                key={word.wordId}
                word={word}
                expanded={expandedWordIds.has(word.wordId)}
                selected={selectedWordIds.has(word.wordId)}
                retrying={retryingWordId === word.wordId}
                retryDisabled={retryingWordId !== null}
                onToggleSelect={onToggleSelect}
                onToggleExpand={onToggleExpand}
                onRetryWord={onRetryWord}
                onOpenDetail={onOpenDetail}
              />
            ))}
          </div>
          {/* 桌面端表格视图 */}
          <div className="hidden overflow-auto rounded-[18px] border border-white/50 shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-sm dark:border-white/[0.08] sm:block">
            <table className="w-full min-w-[840px] text-left text-sm">
              <thead className="bg-black/[0.03] text-xs text-secondary-label dark:bg-white/[0.04]">
                <tr>
                  <th className="w-10 p-3">
                    <label className="grid size-10 cursor-pointer place-items-center">
                      <input type="checkbox" className="size-4.5 accent-accent" aria-label="选择当前页全部词条" checked={allVisibleSelected} onChange={(event) => onToggleAllVisible(event.target.checked)} />
                    </label>
                  </th>
                  <th className="min-w-[160px] p-3">词条</th>
                  <th className="whitespace-nowrap p-3">状态</th>
                  <th className="min-w-[180px] p-3">错误</th>
                  <th className="w-24 p-3">操作</th>
                </tr>
              </thead>
              <tbody>
                {words.map((word) => {
                  const expanded = expandedWordIds.has(word.wordId);
                  return (
                    <DesktopWordRows
                      key={word.wordId}
                      word={word}
                      expanded={expanded}
                      selected={selectedWordIds.has(word.wordId)}
                      retrying={retryingWordId === word.wordId}
                      retryDisabled={retryingWordId !== null}
                      onToggleSelect={onToggleSelect}
                      onToggleExpand={onToggleExpand}
                      onRetryWord={onRetryWord}
                      onOpenDetail={onOpenDetail}
                    />
                  );
                })}
              </tbody>
            </table>
          </div>
        </> : <EmptyState title="暂无初始化任务" description="导入 CSV 后，初始化任务会显示在这里。" />}
      </CardContent>
    </Card>
  );
}

interface WordRowProps {
  word: InitializationWord;
  expanded: boolean;
  selected: boolean;
  retrying: boolean;
  retryDisabled: boolean;
  onToggleSelect: (wordId: number) => void;
  onToggleExpand: (wordId: number) => void;
  onRetryWord: (wordId: number) => void;
  onOpenDetail: (taskId: number) => void;
}

function RetryButton({ word, retrying, retryDisabled, onRetryWord, className }: { word: InitializationWord; retrying: boolean; retryDisabled: boolean; onRetryWord: (wordId: number) => void; className?: string }) {
  if (word.failedTaskCount <= 0) return null;
  return (
    <Button variant="outline" size="sm" className={className} disabled={retryDisabled} onClick={(event) => { event.stopPropagation(); onRetryWord(word.wordId); }}>
      {retrying ? <Loader2 className="size-3.5 animate-spin" /> : <RotateCcw className="size-3.5" />}重试
    </Button>
  );
}

function TaskRow({ task, compact, onOpenDetail }: { task: InitializationTask; compact?: boolean; onOpenDetail: (taskId: number) => void }) {
  return (
    <button
      type="button"
      className={`block w-full rounded-[13px] border border-white/60 bg-white/55 text-left shadow-[0_3px_12px_rgba(0,0,0,0.03)] transition hover:border-accent/25 hover:bg-white/75 dark:border-white/[0.07] dark:bg-white/[0.04] dark:hover:bg-white/[0.07] ${compact ? "p-2.5" : "rounded-[14px] p-3"}`}
      onClick={() => onOpenDetail(task.id)}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className={`flex items-center gap-2 font-medium ${compact ? "text-xs" : ""}`}>
          {TASK_TYPE_LABELS[task.taskType] ?? task.taskType}
          <InitializationBadge status={task.status} />
        </span>
        <span className={`text-quaternary-label ${compact ? "text-[11px]" : "text-xs"}`}>任务 #{task.id}</span>
      </div>
      <div className={`mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-secondary-label ${compact ? "text-[11px]" : "text-xs"}`}>
        <span>重试 {task.attemptCount}/{task.maxAttempts}</span>
        <span>更新时间：{formatTs(task.updatedAt)}</span>
        {task.lastError && <span className="max-w-full truncate text-danger">{task.lastError}</span>}
      </div>
    </button>
  );
}

function MobileWordCard({ word, expanded, selected, retrying, retryDisabled, onToggleSelect, onToggleExpand, onRetryWord, onOpenDetail }: WordRowProps) {
  const completionPercent = word.taskCount ? Math.round(word.completedTaskCount / word.taskCount * 100) : 0;
  return (
    <div className="glass-inner rounded-[18px] p-3.5">
      <div className="flex items-start gap-2.5">
        <label className="grid size-9 shrink-0 cursor-pointer place-items-center rounded-[11px] bg-black/[0.025] dark:bg-white/[0.05]" onClick={(event) => event.stopPropagation()}>
          <input type="checkbox" className="size-4 accent-accent" aria-label={`选择 ${word.term}`} checked={selected} onChange={() => onToggleSelect(word.wordId)} />
        </label>
        <div className="min-w-0 flex-1">
          <div className="flex min-w-0 items-center gap-2">
            <button type="button" className="grid size-7 shrink-0 place-items-center rounded-[9px] bg-accent/[0.08] text-accent" onClick={() => onToggleExpand(word.wordId)} aria-label={expanded ? `收起 ${word.term}` : `展开 ${word.term}`}>
              {expanded ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
            </button>
            <Link href={`/words/${word.wordId}`} className="flex min-w-0 items-center gap-1 truncate font-semibold text-accent" onClick={(event) => event.stopPropagation()}>
              {word.term}<ExternalLink className="size-3 shrink-0" />
            </Link>
          </div>
          <span className="mt-1.5 block text-xs text-quaternary-label">{word.completedTaskCount}/{word.taskCount} 已完成{word.activeTaskCount > 0 ? ` · ${word.activeTaskCount} 个处理中` : ""}</span>
        </div>
        <InitializationBadge status={word.status} />
      </div>
      <div className="mt-3 pl-[3.25rem]">
        <div className="flex items-center justify-between gap-2 text-[11px] text-quaternary-label"><span>初始化进度</span><span>{completionPercent}%</span></div>
        <Progress value={word.completedTaskCount} max={Math.max(1, word.taskCount)} className="mt-1.5 h-1.5" />
        <div className="mt-2 flex items-center justify-between gap-2">
          <span className="truncate text-[11px] text-tertiary-label">{word.errorSummary ?? `更新时间：${formatTs(word.updatedAt)}`}</span>
          <RetryButton word={word} retrying={retrying} retryDisabled={retryDisabled} onRetryWord={onRetryWord} className="h-8 shrink-0 px-2.5 text-xs" />
        </div>
      </div>
      {expanded && (
        <div className="mt-3 space-y-2 border-t border-black/[0.05] pt-3 dark:border-white/[0.08]">
          {word.tasks.map((task) => <TaskRow key={task.id} task={task} compact onOpenDetail={onOpenDetail} />)}
        </div>
      )}
    </div>
  );
}

function DesktopWordRows({ word, expanded, selected, retrying, retryDisabled, onToggleSelect, onToggleExpand, onRetryWord, onOpenDetail }: WordRowProps) {
  return (
    <>
      <tr
        className="cursor-pointer border-t border-black/[0.04] transition hover:bg-black/[0.02] dark:border-white/[0.06] dark:hover:bg-white/[0.03]"
        onClick={() => onToggleExpand(word.wordId)}
      >
        <td className="p-3" onClick={(event) => event.stopPropagation()}>
          <label className="grid size-10 cursor-pointer place-items-center">
            <input type="checkbox" className="size-4.5 accent-accent" aria-label={`选择 ${word.term}`} checked={selected} onChange={() => onToggleSelect(word.wordId)} />
          </label>
        </td>
        <td className="p-3 font-medium">
          <div className="flex items-center gap-2">
            <span className="grid size-7 shrink-0 place-items-center rounded-[10px] bg-accent/[0.08] text-accent">
              {expanded ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
            </span>
            <Link href={`/words/${word.wordId}`} className="text-accent hover:underline" onClick={(event) => event.stopPropagation()}>
              <span className="inline-flex items-center gap-1">{word.term}<ExternalLink className="size-3" /></span>
            </Link>
          </div>
          <div className="mt-1 pl-9 text-xs font-normal text-quaternary-label">
            <span className="font-medium">{word.completedTaskCount}/{word.taskCount}</span>
            <span className="ml-1">已完成</span>
            {word.activeTaskCount > 0 && <span className="ml-2 text-accent">· {word.activeTaskCount} 个处理中</span>}
          </div>
        </td>
        <td className="whitespace-nowrap p-3">
          <div><InitializationBadge status={word.status} /></div>
          <div className="mt-1 text-xs text-secondary-label">{formatTs(word.updatedAt)}</div>
        </td>
        <td className="max-w-xs truncate p-3 text-xs text-danger">{word.errorSummary ?? (word.failedTaskCount ? `有 ${word.failedTaskCount} 个失败子任务` : "—")}</td>
        <td className="p-3">
          <RetryButton word={word} retrying={retrying} retryDisabled={retryDisabled} onRetryWord={onRetryWord} />
        </td>
      </tr>
      {expanded && (
        <tr className="border-t border-black/[0.03] bg-accent/[0.025] dark:border-white/[0.04] dark:bg-white/[0.02]">
          <td colSpan={5} className="px-5 py-3">
            <div className="space-y-2 pl-9">
              {word.tasks.map((task) => <TaskRow key={task.id} task={task} onOpenDetail={onOpenDetail} />)}
            </div>
          </td>
        </tr>
      )}
    </>
  );
}
