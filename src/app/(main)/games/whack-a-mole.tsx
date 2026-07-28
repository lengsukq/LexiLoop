"use client";

import { useEffect, useRef, useState } from "react";
import { playCachedTts } from "@/lib/tts-client";
import type { GameItem } from "./types";

const HOLE_COUNT = 6;
const MOLE_STAY_MS = 2800;
const STAGGER_MS = 130;

type MoleState = "hidden" | "up" | "whacked" | "shaking" | "hiding";

interface Mole {
  hole: number;
  word: string;
  state: MoleState;
}

function shuffle<T>(items: T[]): T[] {
  const output = [...items];
  for (let index = output.length - 1; index > 0; index -= 1) {
    const randomIndex = Math.floor(Math.random() * (index + 1));
    [output[index], output[randomIndex]] = [output[randomIndex]!, output[index]!];
  }
  return output;
}

export function WhackAMole({ item, onSolved, onMistake, onFailed }: {
  item: GameItem;
  onSolved: (item: GameItem) => void;
  onMistake: (item: GameItem) => void;
  onFailed: (item: GameItem) => void;
}) {
  const [moles, setMoles] = useState<Mole[]>(() => {
    const holes = shuffle(Array.from({ length: HOLE_COUNT }, (_, index) => index)).slice(0, item.choices.length);
    return item.choices.map((word, index) => ({ hole: holes[index]!, word, state: "hidden" as MoleState }));
  });
  const solvedRef = useRef(false);

  useEffect(() => {
    const popTimers = item.choices.map((_, index) => window.setTimeout(() => {
      setMoles((prev) => prev.map((mole, moleIndex) => moleIndex === index && mole.state === "hidden" ? { ...mole, state: "up" } : mole));
    }, 150 + STAGGER_MS * index));

    let hideTimer: number | undefined;
    const failTimer = window.setTimeout(() => {
      if (solvedRef.current) return;
      setMoles((prev) => prev.map((mole) => ({ ...mole, state: "hiding" as MoleState })));
      hideTimer = window.setTimeout(() => onFailed(item), 320);
    }, 150 + STAGGER_MS * item.choices.length + MOLE_STAY_MS);

    return () => {
      popTimers.forEach((timer) => window.clearTimeout(timer));
      window.clearTimeout(failTimer);
      if (hideTimer) window.clearTimeout(hideTimer);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function whack(mole: Mole) {
    if (mole.state !== "up" || solvedRef.current) return;
    void playCachedTts(mole.word, "US");
    if (mole.word === item.term) {
      solvedRef.current = true;
      setMoles((prev) => prev.map((entry) => entry.word === mole.word ? { ...entry, state: "whacked" as MoleState } : { ...entry, state: "hiding" as MoleState }));
      window.setTimeout(() => onSolved(item), 430);
    } else {
      onMistake(item);
      setMoles((prev) => prev.map((entry) => entry.hole === mole.hole ? { ...entry, state: "shaking" as MoleState } : entry));
      window.setTimeout(() => {
        setMoles((prev) => prev.map((entry) => entry.hole === mole.hole && entry.state === "shaking" ? { ...entry, state: "up" as MoleState } : entry));
      }, 400);
    }
  }

  const moleByHole = new Map(moles.map((mole) => [mole.hole, mole]));

  return <div className="text-center">
    <p className="text-[13px] text-[#8e8e93]">看释义，锤出正确的单词地鼠</p>
    <h1 className="mx-auto mt-3 max-w-xl text-xl font-bold leading-relaxed sm:text-2xl">{item.definition}</h1>
    <div key={item.itemId} className="mx-auto mt-7 grid max-w-lg grid-cols-3 gap-x-3 gap-y-5 sm:gap-x-5">
      {Array.from({ length: HOLE_COUNT }, (_, hole) => {
        const mole = moleByHole.get(hole);
        const stateClass = !mole || mole.state === "hidden"
          ? "translate-y-[115%] opacity-0"
          : mole.state === "up"
            ? "animate-[mole-pop_0.32s_cubic-bezier(0.34,1.56,0.64,1)_forwards]"
            : mole.state === "whacked"
              ? "animate-[mole-squish_0.42s_ease-in_forwards]"
              : mole.state === "hiding"
                ? "animate-[mole-hide_0.3s_ease-in_forwards]"
                : "animate-[shake_0.35s_ease-in-out]";
        return <div key={hole} className="flex flex-col items-center">
          <div className="relative h-24 w-full overflow-hidden sm:h-28">
            {mole && <button type="button" onClick={() => whack(mole)} className={`absolute inset-x-1 bottom-0 flex flex-col items-center rounded-t-[22px] bg-gradient-to-b from-[#c98a4b] to-[#8b5e34] px-1 pb-2 pt-2.5 shadow-[inset_0_2px_0_rgba(255,255,255,0.25),0_6px_16px_rgba(0,0,0,0.18)] transition-transform active:scale-95 ${stateClass}`}>
              <span className="text-lg leading-none">🐹</span>
              <span className="mt-1 line-clamp-1 text-[12px] font-bold text-white sm:text-[13px]">{mole.word}</span>
            </button>}
          </div>
          <div className="-mt-1.5 h-4 w-[86%] rounded-[50%] bg-gradient-to-b from-[#3a2d1f] to-[#57432e] shadow-[inset_0_3px_6px_rgba(0,0,0,0.5)]" />
        </div>;
      })}
    </div>
    <p className="mt-5 text-xs text-[#aeaeb2]">地鼠缩回前锤中正确单词 · 锤错会记一次失误</p>
  </div>;
}
