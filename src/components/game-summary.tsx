"use client";

import { CheckCircle2, Flame, ListChecks, Volume2, XCircle } from "lucide-react";
import { playCachedTts } from "@/lib/tts-client";

export type SummaryStatus = "correct" | "recovered" | "missed";

export interface SummaryItem {
  term: string;
  definition: string;
  phonetic?: string;
  status: SummaryStatus;
}

const STATUS_META: Record<SummaryStatus, { label: string; icon: React.ReactNode; tone: string }> = {
  correct: {
    label: "一次答对",
    icon: <CheckCircle2 className="size-4 text-success" />,
    tone: "text-success-deep",
  },
  recovered: {
    label: "纠正后答对",
    icon: <Flame className="size-4 text-warning" />,
    tone: "text-warning-deep",
  },
  missed: {
    label: "未完成",
    icon: <XCircle className="size-4 text-danger" />,
    tone: "text-danger-deep",
  },
};

function SummaryRow({ item }: { item: SummaryItem }) {
  const meta = STATUS_META[item.status];
  return <li className="flex items-center gap-3 rounded-[14px] glass-inner border border-white/40 px-3 py-2.5 dark:border-white/[0.08]">
    <span className="grid size-8 shrink-0 place-items-center rounded-full bg-black/[0.04] dark:bg-white/[0.06]">{meta.icon}</span>
    <span className="min-w-0 flex-1">
      <span className="flex flex-wrap items-baseline gap-x-2">
        <b className="break-words text-[15px]">{item.term}</b>
        {item.phonetic && <small className="font-mono text-xs text-quaternary-label">{item.phonetic}</small>}
        <small className={`text-[11px] font-semibold ${meta.tone}`}>{meta.label}</small>
      </span>
      <small className="mt-0.5 line-clamp-2 block text-xs leading-snug text-quaternary-label">{item.definition}</small>
    </span>
    <button type="button" onClick={() => void playCachedTts(item.term, "US")} className="ios-press grid size-9 shrink-0 place-items-center rounded-full bg-accent/10 text-accent"><Volume2 className="size-4" /></button>
  </li>;
}

export function GameSummary({ items }: { items: SummaryItem[] }) {
  if (!items.length) return null;
  const needWork = items.filter((item) => item.status !== "correct");
  const correct = items.filter((item) => item.status === "correct");

  return <div className="space-y-3 rounded-[18px] border border-white/40 bg-white/40 p-4 backdrop-blur-xl dark:border-white/[0.08] dark:bg-white/[0.04]">
    <div className="flex items-center gap-2"><ListChecks className="size-4 text-accent" /><b className="text-[15px]">本轮词条总结</b><small className="text-xs text-quaternary-label">共 {items.length} 条</small></div>
    {needWork.length > 0 && <div>
      <p className="mb-2 text-xs font-semibold text-warning-deep">需加强 · {needWork.length} 条</p>
      <ul className="max-h-64 space-y-2 overflow-y-auto pr-1">
        {needWork.map((item) => <SummaryRow key={`${item.term}-${item.status}`} item={item} />)}
      </ul>
    </div>}
    {correct.length > 0 && <div>
      <p className="mb-2 text-xs font-semibold text-success-deep">已答对 · {correct.length} 条</p>
      <ul className="max-h-64 space-y-2 overflow-y-auto pr-1">
        {correct.map((item) => <SummaryRow key={`${item.term}-${item.status}`} item={item} />)}
      </ul>
    </div>}
  </div>;
}
