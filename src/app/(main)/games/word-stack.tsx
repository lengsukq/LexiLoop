"use client";

import { useRef, useState } from "react";
import { playCachedTts } from "@/lib/tts-client";
import type { GameItem } from "./types";

const TOWER_COLORS = [
  "from-[#ff9500] to-[#ff6961]",
  "from-[#5ac8fa] to-[#007aff]",
  "from-[#af52de] to-[#5856d6]",
  "from-[#34c759] to-[#00c7be]",
];

export function WordStack({ item, solvedTerms, onSolved, onMistake }: {
  item: GameItem;
  solvedTerms: string[];
  onSolved: (item: GameItem) => void;
  onMistake: (item: GameItem) => void;
}) {
  const [dropped, setDropped] = useState<Set<string>>(new Set());
  const [popped, setPopped] = useState<string | null>(null);
  const solvedRef = useRef(false);

  function tapBlock(word: string) {
    if (solvedRef.current || popped || dropped.has(word)) return;
    void playCachedTts(word, "US");
    if (word === item.term) {
      solvedRef.current = true;
      setPopped(word);
      window.setTimeout(() => onSolved(item), 400);
    } else {
      onMistake(item);
      setDropped((prev) => new Set(prev).add(word));
      window.setTimeout(() => {
        setDropped((prev) => {
          const next = new Set(prev);
          next.delete(word);
          return next;
        });
      }, 620);
    }
  }

  const rows = [item.choices.slice(0, 2), item.choices.slice(2, 4)];
  const tower = solvedTerms.slice(-4);

  function renderRow(rowChoices: string[], direction: "left" | "right", duration: string) {
    const copies = [0, 1, 2];
    return <div className="relative overflow-hidden">
      <div className="flex w-max gap-4 py-1.5" style={{ animation: `block-scroll-${direction} ${duration} linear infinite` }}>
        {copies.map((copy) => rowChoices.map((word) => {
          const isDropped = dropped.has(word);
          const isPopped = popped === word;
          const stateClass = isPopped
            ? "scale-125 opacity-0 transition-all duration-300"
            : isDropped
              ? "animate-[block-drop_0.6s_ease-in_forwards]"
              : "";
          return <button key={`${copy}-${word}`} type="button" onClick={() => tapBlock(word)}
            className={`ios-press shrink-0 rounded-[15px] border border-white/50 bg-gradient-to-b from-white/90 to-[#f2f2f7] px-5 py-3 text-[15px] font-bold text-[#1c1c1e] shadow-[0_5px_14px_rgba(0,0,0,0.1)] dark:border-white/[0.1] dark:from-white/[0.12] dark:to-white/[0.06] dark:text-white ${stateClass}`}>
            {word}
          </button>;
        }))}
      </div>
    </div>;
  }

  return <div className="text-center">
    <p className="text-[13px] text-[#8e8e93]">看释义，点选滚动词块堆高塔</p>
    <h1 className="mx-auto mt-3 max-w-xl text-xl font-bold leading-relaxed sm:text-2xl">{item.definition}</h1>

    <div key={item.itemId} className="mx-auto mt-7 max-w-xl space-y-3 rounded-[18px] border border-[#ff2d55]/15 bg-[#ff2d55]/[0.04] px-2 py-4">
      {renderRow(rows[0]!, "left", "11s")}
      {renderRow(rows[1]!, "right", "14s")}
    </div>

    <div className="mx-auto mt-6 flex min-h-[104px] max-w-xs flex-col-reverse items-center justify-start gap-1">
      {tower.map((term, index) => {
        const color = TOWER_COLORS[(solvedTerms.length - tower.length + index) % TOWER_COLORS.length];
        const isLatest = index === tower.length - 1;
        return <div key={`${term}-${index}`} className={`flex h-9 w-36 items-center justify-center rounded-[10px] bg-gradient-to-r px-2 text-[12px] font-bold text-white shadow-md ${color} ${isLatest ? "animate-[tower-bounce_0.45s_cubic-bezier(0.34,1.56,0.64,1)]" : ""}`}>
          <span className="line-clamp-1">{term}</span>
        </div>;
      })}
      {tower.length === 0 && <p className="mt-8 text-xs text-[#aeaeb2]">点对词块，塔会越堆越高</p>}
    </div>
    <p className="mt-2 text-xs text-[#aeaeb2]">已堆 {solvedTerms.length} 层 · 点错会记一次失误</p>
  </div>;
}
