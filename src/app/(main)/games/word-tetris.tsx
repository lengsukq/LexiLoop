"use client";

import { useEffect, useRef, useState } from "react";
import { shuffle } from "@/lib/array";
import { playCachedTts } from "@/lib/tts-client";
import type { GameItem } from "./types";

const FALL_MIN_MS = 4200;
const FALL_SPREAD_MS = 1800;

const STACK_COLORS = [
  "from-[#5856d6] to-[#af52de]",
  "from-[#007aff] to-[#5ac8fa]",
  "from-[#ff2d55] to-[#ff9500]",
  "from-[#34c759] to-[#00c7be]",
  "from-[#ff9500] to-[#ff6961]",
];

type BlockState = "falling" | "shaking" | "smashed" | "landed";

interface Block {
  word: string;
  col: number;
  duration: number;
  state: BlockState;
}

export function WordTetris({ item, danger, dangerCap, onSolved, onMistake, onLand }: {
  item: GameItem;
  danger: number;
  dangerCap: number;
  onSolved: (item: GameItem) => void;
  onMistake: (item: GameItem) => void;
  onFailed: (item: GameItem) => void;
  onLand: (word: string) => void;
}) {
  const [blocks, setBlocks] = useState<Block[]>(() => {
    const cols = shuffle([0, 1, 2, 3]);
    return item.choices.map((word, index) => ({
      word,
      col: cols[index] ?? index,
      duration: FALL_MIN_MS + Math.round(Math.random() * FALL_SPREAD_MS),
      state: "falling" as BlockState,
    }));
  });
  const doneRef = useRef(false);
  const resolvedRef = useRef<boolean[]>(item.choices.map(() => false));
  const onLandRef = useRef(onLand);
  useEffect(() => {
    onLandRef.current = onLand;
  });

  useEffect(() => {
    const timers = blocks.map((block, index) => window.setTimeout(() => {
      if (doneRef.current || resolvedRef.current[index]) return;
      resolvedRef.current[index] = true;
      setBlocks((prev) => prev.map((entry, entryIndex) =>
        entryIndex === index ? { ...entry, state: "landed" as BlockState } : entry,
      ));
      if (block.word === item.term) doneRef.current = true;
      onLandRef.current(block.word);
    }, block.duration));
    return () => timers.forEach((timer) => window.clearTimeout(timer));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function tap(block: Block) {
    const index = blocks.findIndex((entry) => entry.word === block.word);
    if (doneRef.current || block.state !== "falling" || (index >= 0 && resolvedRef.current[index])) return;
    void playCachedTts(block.word, "US");
    if (block.word === item.term) {
      doneRef.current = true;
      if (index >= 0) resolvedRef.current[index] = true;
      setBlocks((prev) => prev.map((entry) => entry.word === block.word ? { ...entry, state: "smashed" as BlockState } : entry));
      window.setTimeout(() => onSolved(item), 420);
    } else {
      onMistake(item);
      setBlocks((prev) => prev.map((entry) => entry.word === block.word ? { ...entry, state: "shaking" as BlockState } : entry));
      window.setTimeout(() => {
        setBlocks((prev) => prev.map((entry) => entry.word === block.word && entry.state === "shaking" ? { ...entry, state: "falling" as BlockState } : entry));
      }, 380);
    }
  }

  const urgent = danger >= dangerCap - 1;

  return <div className="text-center">
    <p className="text-[13px] text-[#8e8e93]">看释义，点中正在下落的正确单词</p>
    <h1 className="mx-auto mt-3 max-w-xl text-xl font-bold leading-relaxed sm:text-2xl">{item.definition}</h1>
    <div className="relative mx-auto mt-6 h-[420px] max-w-lg overflow-hidden rounded-[18px] border border-[#5856d6]/15 bg-gradient-to-b from-[#5856d6]/[0.05] to-[#af52de]/[0.08]">
      {blocks.map((block) => {
        const innerClass = block.state === "smashed"
          ? "animate-[tetris-smash_0.42s_ease-out_forwards]"
          : block.state === "landed"
            ? "opacity-0 transition-opacity duration-300"
            : block.state === "shaking"
              ? "animate-[shake_0.35s_ease-in-out]"
              : "";
        return <div
          key={block.word}
          className="absolute top-[-64px] w-[calc(25%-8px)]"
          style={{ left: `calc(${block.col} * 25% + 4px)`, animation: `tetris-fall ${block.duration}ms linear forwards` }}
        >
          <button
            type="button"
            onClick={() => tap(block)}
            className={`ios-press flex h-14 w-full items-center justify-center rounded-[13px] border border-white/50 bg-gradient-to-b px-1 shadow-[0_6px_16px_rgba(88,86,214,0.25)] ${STACK_COLORS[block.col % STACK_COLORS.length]} ${innerClass}`}
          >
            <span className="line-clamp-1 break-all text-[12px] font-bold text-white">{block.word}</span>
          </button>
        </div>;
      })}
      <div className="pointer-events-none absolute inset-x-0 bottom-0 flex flex-col-reverse gap-[3px] px-1 pb-1">
        {Array.from({ length: danger }, (_, index) => {
          const isTop = index === danger - 1;
          return <div
            key={`stack-${index}`}
            className={`h-[13px] rounded-[6px] bg-gradient-to-r opacity-80 ${STACK_COLORS[index % STACK_COLORS.length]} ${isTop ? "animate-[tetris-stack-in_0.3s_ease-out]" : ""}`}
          />;
        })}
      </div>
    </div>
    <p className={`mt-4 text-xs ${urgent ? "font-bold text-[#ff3b30] dark:text-[#ff453a]" : "text-[#aeaeb2]"}`}>堆叠 {danger}/{dangerCap} · 点错会记一次失误 · 堆满结束本轮</p>
  </div>;
}
