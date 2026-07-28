import { Crown, Flame, Medal, Trophy } from "lucide-react";
import type { LeaderboardSummary } from "@/lib/types";
import { cn } from "@/lib/cn";

function formatPlayedAt(value: number): string {
  return new Intl.DateTimeFormat("zh-CN", { month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" }).format(new Date(value));
}

const RANK_STYLES: Record<number, string> = {
  1: "bg-gradient-to-b from-[#ffd60a] to-[#ff9f0a] text-[#7a4c00] shadow-[0_3px_10px_rgba(255,159,10,0.4)]",
  2: "bg-gradient-to-b from-[#e5e5ea] to-[#aeaeb2] text-[#48484a] shadow-[0_3px_10px_rgba(174,174,178,0.4)]",
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
        ? "bg-gradient-to-r from-[#ffd60a]/20 to-[#ff9f0a]/15 shadow-[inset_0_1px_0_rgba(255,214,10,0.4)]"
        : leaderboard.inTop10
          ? "bg-[#34c759]/[0.08]"
          : "bg-black/[0.03] dark:bg-white/[0.05]",
    )}>
      <span className="flex items-center gap-2 text-sm font-semibold">
        {leaderboard.isNewBest
          ? <><Crown className="size-4 text-[#ff9f0a]" /><span className="text-[#8a5a00] dark:text-[#ffd60a]">新纪录！第 1 名</span></>
          : leaderboard.inTop10
            ? <><Trophy className="size-4 text-[#34c759]" /><span className="text-[#248a3d] dark:text-[#30d158]">本轮排名 第 {leaderboard.rank} 名</span></>
            : <span className="text-[#8e8e93]">本轮 第 {leaderboard.rank} 名 · 未进前十</span>}
      </span>
      <span className="text-xs text-[#8e8e93]">历史最佳 {leaderboard.best}</span>
    </div>

    <div>
      <p className="mb-2 text-xs font-semibold text-[#8e8e93]">{title}</p>
      <div className="space-y-1.5">
        {leaderboard.top.map((entry, index) => {
          const rank = index + 1;
          return <div key={`${entry.playedAt}-${rank}`} className={cn(
            "flex items-center gap-3 rounded-[14px] border px-3 py-2 transition-all",
            entry.isCurrent
              ? "border-[#007aff]/35 bg-[#007aff]/[0.07] shadow-[0_4px_16px_rgba(0,122,255,0.1)]"
              : "border-transparent bg-black/[0.025] dark:bg-white/[0.04]",
          )}>
            <span className={cn(
              "grid size-7 shrink-0 place-items-center rounded-full text-[12px] font-black",
              RANK_STYLES[rank] ?? "bg-black/[0.05] text-[#8e8e93] dark:bg-white/[0.08]",
            )}>{rank <= 3 ? <Medal className="size-3.5" /> : rank}</span>
            <span className={cn("min-w-0 flex-1 truncate text-[15px] font-bold", entry.isCurrent ? "text-[#007aff] dark:text-[#0a84ff]" : "text-[#1c1c1e] dark:text-[#f5f5f7]")}>
              {entry.score}
              {entry.isCurrent && <span className="ml-2 rounded-full bg-[#007aff]/12 px-2 py-0.5 text-[10px] font-semibold text-[#007aff] dark:text-[#0a84ff]">本轮</span>}
            </span>
            <span className="flex items-center gap-1 text-xs text-[#8e8e93]"><Flame className="size-3" />{entry.maxCombo}</span>
            <span className="w-20 text-right text-xs tabular-nums text-[#aeaeb2]">{formatPlayedAt(entry.playedAt)}</span>
          </div>;
        })}
      </div>
    </div>
  </div>;
}
