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
    <Card>
      <CardContent className="pt-5">
        <div className="grid gap-5 lg:grid-cols-[minmax(240px,0.9fr)_minmax(0,1.4fr)] lg:items-center">
          <div>
            <div className="flex items-end justify-between gap-3">
              <div>
                <p className="text-sm font-semibold">词条初始化进度</p>
                <p className="mt-1 text-xs text-quaternary-label">已完成 {wordCompleted} / {wordTotal}</p>
              </div>
              <b className="text-2xl tracking-tight">{wordTotal ? Math.round(wordCompleted / wordTotal * 100) : 0}%</b>
            </div>
            <Progress value={wordCompleted} max={Math.max(1, wordTotal)} className="mt-3" />
          </div>
          <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {STATUS_TILES.map((tile) => {
              const value = status.summary[tile.key] ?? 0;
              return (
                <div key={tile.key} className="flex items-center gap-3 rounded-[14px] bg-black/[0.025] p-3 dark:bg-white/[0.035]">
                  <span className={`grid size-9 shrink-0 place-items-center rounded-[11px] ${tile.className}`}>
                    <tile.icon className={`size-4 ${tile.key === "RUNNING" && value > 0 ? "animate-spin" : ""}`} />
                  </span>
                  <div>
                    <b className="block text-lg leading-none">{value}</b>
                    <span className="mt-1 block text-xs text-quaternary-label">{tile.label}</span>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
        {runMessage && <p className="mt-3 text-xs text-accent">{runMessage}</p>}
        {hasFailedWords && (
          <Button className="mt-4" variant="outline" size="sm" onClick={onRetryFailed} disabled={retrying}>
            {retrying ? <Loader2 className="size-4 animate-spin" /> : <RotateCcw className="size-4" />}重试当前失败词条
          </Button>
        )}
      </CardContent>
    </Card>
  );
}
