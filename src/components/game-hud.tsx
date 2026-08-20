"use client";

import type { ReactNode } from "react";
import { Clock3, Flame, Loader2 } from "lucide-react";
import { formatClockTime } from "@/lib/format";
import { Badge } from "@/components/ui";

/** Countdown pill shown in the play header; turns red and pulses when time is low. */
export function GameTimerPill({ remainingMs, urgentAt = 10_000 }: { remainingMs: number; urgentAt?: number }) {
  const urgent = remainingMs <= urgentAt;
  return <div className={`flex items-center gap-2 rounded-full px-4 py-2 font-mono text-lg font-bold ${urgent ? "animate-pulse bg-danger/10 text-danger" : "bg-accent/10 text-accent"}`}>
    <Clock3 className="size-5" />{formatClockTime(remainingMs)}
  </div>;
}

/** Combo counter badge; highlights once the combo reaches 3. */
export function GameComboBadge({ combo }: { combo: number }) {
  return <Badge tone={combo >= 3 ? "amber" : "slate"}><Flame className="size-3.5" />{combo} 连击</Badge>;
}

/**
 * Top bar shown while playing: caller-provided exit control, the countdown pill
 * and the combo badge. `exit` stays caller-owned because match navigates home
 * (Link) while games/phonetics reset locally (button).
 */
export function GamePlayHeader({ remainingMs, combo, exit }: { remainingMs: number; combo: number; exit: ReactNode }) {
  return <div className="flex flex-wrap items-center justify-between gap-3">
    {exit}
    <GameTimerPill remainingMs={remainingMs} />
    <GameComboBadge combo={combo} />
  </div>;
}

/** Full-screen overlay shown while a finished game is being saved. */
export function GameSavingOverlay({ message = "正在结算并更新错词…" }: { message?: string }) {
  return <div className="fixed inset-0 z-50 grid place-items-center bg-black/20 backdrop-blur-sm">
    <div className="liquid-glass-elevated rounded-[22px] px-7 py-6 text-center">
      <Loader2 className="mx-auto size-8 animate-spin text-accent" />
      <p className="mt-3 text-sm font-semibold">{message}</p>
    </div>
  </div>;
}

/**
 * Inline error banner. When `onRetry` is provided a "重试保存" action is shown
 * (playing phase); otherwise a plain message is rendered (setup phase).
 */
export function GameErrorBanner({ error, onRetry }: { error: string; onRetry?: () => void }) {
  if (!error) return null;
  if (!onRetry) {
    return <div className="rounded-[14px] bg-danger/[0.08] p-3 text-sm text-danger-deep">{error}</div>;
  }
  return <div className="flex items-center justify-between gap-3 rounded-[14px] bg-danger/[0.08] p-3 text-sm text-danger-deep">
    <span>{error}</span>
    <button type="button" className="font-semibold" onClick={onRetry}>重试保存</button>
  </div>;
}
