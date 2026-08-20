import Link from "next/link";
import { Loader2, Sparkles } from "lucide-react";
import { Alert, Badge, Button, Dialog } from "@/components/ui";
import { InitializationBadge } from "@/components/status-badges";
import {
  MODE_LABELS, TASK_TYPE_LABELS, contentFieldLabel, durationText, formatTs,
  type JobDetails,
} from "./types";

export function JobDetailDialog({ jobId, data, loading, error, queueing, onClose, onQueueWord }: {
  jobId: number | null;
  data: JobDetails | null;
  loading: boolean;
  error: string;
  queueing: boolean;
  onClose: () => void;
  onQueueWord: () => void;
}) {
  return (
    <Dialog open={jobId !== null} onClose={onClose} title={data ? `任务 #${data.job.id} 详情` : "任务详情"}>
      {loading && <div className="flex items-center justify-center py-8"><Loader2 className="size-6 animate-spin text-accent" /></div>}
      {error && <Alert>{error}</Alert>}
      {data && (
        <div className="space-y-4">
          <div className="grid grid-cols-2 gap-3 text-sm">
            <DetailField label="状态"><InitializationBadge status={data.job.status} /></DetailField>
            <DetailField label="词条">
              <Link href={`/words/${data.job.wordId}`} className="font-medium text-accent hover:underline" onClick={onClose}>
                {data.job.term}
              </Link>
            </DetailField>
            <DetailField label="模式">{MODE_LABELS[data.job.mode] ?? data.job.mode}</DetailField>
            <DetailField label="任务类型">{TASK_TYPE_LABELS[data.job.taskType] ?? data.job.taskType}</DetailField>
            <DetailField label="重试">{data.job.attemptCount}/{data.job.maxAttempts}</DetailField>
            <DetailField label="更新时间" className="col-span-2">{formatTs(data.job.updatedAt)}</DetailField>
            {data.job.lastError && (
              <div className="col-span-2">
                <span className="text-tertiary-label">错误信息</span>
                <p className="mt-0.5 whitespace-pre-wrap rounded-[12px] border border-danger/10 bg-danger/[0.05] p-2 text-xs text-danger backdrop-blur-sm">
                  {data.job.lastError}
                  {data.job.lastErrorCode && <span className="ml-2 font-mono opacity-60">({data.job.lastErrorCode})</span>}
                </p>
              </div>
            )}
          </div>

          <div className="rounded-[16px] border border-accent/10 bg-accent/[0.04] p-3">
            <p className="text-xs leading-5 text-secondary-label">此操作会为「{data.job.term}」补全缺失的释义、例句、助记等内容；手动编辑的释义和例句会保留。</p>
            <Button className="mt-3" size="sm" onClick={onQueueWord} disabled={queueing}>
              {queueing ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}补全这个词
            </Button>
          </div>

          {data.contentFields && <>
            <hr className="border-black/[0.06] dark:border-white/[0.08]" />
            <h3 className="text-sm font-medium">已获取内容字段</h3>
            <div className="flex flex-wrap gap-2 text-xs">
              {Object.entries(data.contentFields).map(([key, present]) => (
                <span key={key} className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 shadow-[0_2px_6px_rgba(0,0,0,0.03)] backdrop-blur-sm ${
                  present
                    ? "border border-success/15 bg-success/[0.08] text-success-deep"
                    : "border border-black/[0.04] bg-black/[0.03] text-tertiary-label dark:border-white/[0.06] dark:bg-white/[0.04]"
                }`}>
                  {present ? "✓" : "○"} {contentFieldLabel(key)}
                </span>
              ))}
            </div>
          </>}

          {data.attempts.length > 0 && <>
            <hr className="border-black/[0.06] dark:border-white/[0.08]" />
            <h3 className="text-sm font-medium">Provider 调用</h3>
            <div className="max-h-48 space-y-2 overflow-y-auto">
              {data.attempts.map((attempt) => (
                <div key={attempt.id} className="rounded-[14px] border border-white/50 bg-white/40 p-3 text-xs shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
                  <div className="flex items-center justify-between gap-2">
                    <span className="font-medium">{attempt.providerId}</span>
                    <Badge tone={attempt.status === "SUCCESS" ? "green" : attempt.status === "EMPTY" ? "amber" : "red"}>{attempt.status}</Badge>
                  </div>
                  <div className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 text-secondary-label">
                    <span>耗时：{durationText(attempt.durationMs)}</span>
                    {attempt.metadata?.model && <span>模型：{attempt.metadata.model}</span>}
                    {attempt.metadata?.qualityScore != null && <span>评分：{attempt.metadata.qualityScore}</span>}
                    {attempt.fieldsReturned.length > 0 && <span>字段：{attempt.fieldsReturned.join("、")}</span>}
                  </div>
                  {attempt.errorMessage && <p className="mt-1 text-danger">{attempt.errorMessage}</p>}
                </div>
              ))}
            </div>
          </>}
        </div>
      )}
    </Dialog>
  );
}

function DetailField({ label, children, className }: { label: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={className}>
      <span className="text-tertiary-label">{label}</span>
      <p className="mt-0.5">{children}</p>
    </div>
  );
}
