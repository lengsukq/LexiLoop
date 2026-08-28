import { AlertCircle, Clock3, Loader2, RotateCcw, XCircle } from "lucide-react";
import { Button, Card, CardContent, Progress } from "@/components/ui";
import type { StatusData } from "./types";

const STATUS_TILES = [
  { label: "排队", key: "QUEUED", icon: Clock3, className: "text-accent bg-accent/10" },
  { label: "处理中", key: "RUNNING", icon: Loader2, className: "text-[#5856d6] bg-[#5856d6]/10" },
  { label: "部分完成", key: "PARTIAL", icon: AlertCircle, className: "text-warning bg-warning/10" },
  { label: "失败", key: "FAILED", icon: XCircle, className: "text-danger bg-danger/10" },
] as const;

export function InitializeProgress({ status, hasFailedWords, runMessage, retrying, onRetryFailed }: {
  status: StatusData;
  hasFailedWords: boolean;
  runMessage: string;
  retrying: boolean;
  onRetryFailed: () => void;
}) {
  const wordTotal = Object.values(status.wordSummary).reduce((sum, value) => sum + value, 0);
  const wordCompleted = (status.wordSummary.READY ?? 0) + (status.wordSummary.PARTIAL ?? 0);

  return (
    <Card className="rounded-[22px]">
      <CardContent className="pt-4.5 sm:pt-5">
        <div className="grid gap-4.5 lg:grid-cols-[minmax(240px,0.9fr)_minmax(0,1.4fr)] lg:items-center">
          <div>
            <div className="flex items-end justify-between gap-3">
              <div>
                <p className="text-sm font-semibold">词条初始化进度</p>
                <p className="mt-0.5 text-xs text-quaternary-label num-tabular">已完成 {wordCompleted} / {wordTotal}</p>
              </div>
              <b className="num-tabular text-2xl font-bold tracking-tight">{wordTotal ? Math.round(wordCompleted / wordTotal * 100) : 0}%</b>
            </div>
            <Progress value={wordCompleted} max={Math.max(1, wordTotal)} className="mt-2.5" />
          </div>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {STATUS_TILES.map((tile) => {
              const value = status.summary[tile.key] ?? 0;
              return (
                <div key={tile.key} className="flex items-center gap-2.5 rounded-[13px] border border-black/[0.05] bg-black/[0.02] p-2.5 dark:border-white/[0.06] dark:bg-white/[0.03]">
                  <span className={`grid size-8 shrink-0 place-items-center rounded-[10px] ${tile.className}`}>
                    <tile.icon className={`size-3.5 ${tile.key === "RUNNING" && value > 0 ? "animate-spin" : ""}`} />
                  </span>
                  <div>
                    <b className="num-tabular block text-base font-bold leading-none">{value}</b>
                    <span className="mt-0.5 block text-[11px] text-quaternary-label">{tile.label}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
        {runMessage && <p className="mt-2.5 text-xs text-accent">{runMessage}</p>}
        {hasFailedWords && (
          <Button className="mt-3.5" variant="outline" size="sm" onClick={onRetryFailed} disabled={retrying}>
            {retrying ? <Loader2 className="size-3.5 animate-spin" /> : <RotateCcw className="size-3.5" />}重试当前失败词条
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
