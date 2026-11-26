import { Crown, Flame, Medal, Trophy } from "lucide-react";
import type { LeaderboardSummary } from "@/lib/types";
import { cn } from "@/lib/cn";

function formatPlayedAt(value: number): string {
  return new Intl.DateTimeFormat("zh-CN", { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

const RANK_STYLES: Record<number, string> = {
  1: "bg-gradient-to-b from-[#ffd60a] to-warning text-[#7a4c00] shadow-[0_3px_10px_rgba(255,159,10,0.4)]",
  2: "bg-gradient-to-b from-[#e5e5ea] to-tertiary-label text-[#48484a] shadow-[0_3px_10px_rgba(174,174,178,0.4)]",
  3: "bg-gradient-to-b from-[#d7a376] to-[#a5673f] text-white shadow-[0_3px_10px_rgba(165,103,63,0.4)]",
};

export function LeaderboardPanel({ leaderboard, title = "历史最佳 · 前十名" }: {
  leaderboard?: LeaderboardSummary;
  title?: string;
}) {
  if (!leaderboard || leaderboard.top.length === 0) return null;

  return <div className="space-y-3">
    <div className={cn(
      "flex items-center justify-between rounded-[16px] px-4 py-3",
      leaderboard.isNewBest
        ? "bg-gradient-to-r from-[#ffd60a]/20 to-warning/15 shadow-[inset_0_1px_0_rgba(255,214,10,0.4)]"
        : leaderboard.inTop10
          ? "bg-success/[0.08]"
          : "bg-black/[0.03] dark:bg-white/[0.05]",
    )}>
      <span className="flex items-center gap-2 text-sm font-semibold">
        {leaderboard.isNewBest
          ? <><Crown className="size-4 text-warning" /><span className="text-[#8a5a00] dark:text-[#ffd60a]">新纪录！第 1 名</span></>
          : leaderboard.inTop10
            ? <><Trophy className="size-4 text-success" /><span className="text-success-deep">本轮排名 第 {leaderboard.rank} 名</span></>
            : <span className="text-quaternary-label">本轮 第 {leaderboard.rank} 名 · 未进前十</span>}
      </span>
      <span className="text-xs text-quaternary-label">历史最佳 {leaderboard.best}</span>
    </div>

    <div>
      <p className="mb-2 text-xs font-semibold text-quaternary-label">{title}</p>
      <div className="space-y-1.5">
        {leaderboard.top.map((entry, index) => {
          const rank = index + 1;
          return <div key={`${entry.playedAt}-${rank}`} className={cn(
            "flex items-center gap-3 rounded-[14px] border px-3 py-2 transition-all",
            entry.isCurrent
              ? "border-accent/35 bg-accent/[0.07] shadow-[0_4px_16px_rgba(0,122,255,0.1)]"
              : "border-transparent bg-black/[0.025] dark:bg-white/[0.04]",
          )}>
            <span className={cn(
              "grid size-7 shrink-0 place-items-center rounded-full text-[12px] font-black",
              RANK_STYLES[rank] ?? "bg-black/[0.05] text-quaternary-label dark:bg-white/[0.08]",
            )}>{rank <= 3 ? <Medal className="size-3.5" /> : rank}</span>
            <span className={cn("min-w-0 flex-1 truncate text-[15px] font-bold", entry.isCurrent ? "text-accent" : "text-label")}>
              {entry.score}
              {entry.isCurrent && <span className="ml-2 rounded-full bg-accent/12 px-2 py-0.5 text-[10px] font-semibold text-accent">本轮</span>}
            </span>
            <span className="flex items-center gap-1 text-xs text-quaternary-label"><Flame className="size-3" />{entry.maxCombo}</span>
            <span className="w-20 text-right text-xs tabular-nums text-tertiary-label">{formatPlayedAt(entry.playedAt)}</span>
          </div>;
        })}
      </div>
    </div>
  </div>;
}
