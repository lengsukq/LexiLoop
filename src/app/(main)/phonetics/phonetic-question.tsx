"use client";

import { useState } from "react";
import { CheckCircle2, Ear, Flame, Volume2, XCircle } from "lucide-react";
import { AudioWave, Badge, Button } from "@/components/ui";
import type { PhoneticGameItem } from "./types";
import { correctChoice } from "./choice";

interface Props {
  item: PhoneticGameItem;
  wrongChoice: string | null;
  correctFeedback: boolean;
  audioError: string;
  onChoose: (choice: string) => void;
  onPlay: () => Promise<void> | void;
  onSkip: () => void;
}

function Prompt({ item, onPlay, isPlaying }: Pick<Props, "item"> & { onPlay: () => void; isPlaying: boolean }) {
  if (item.challengeType === "SOUND_TO_PHONETIC") {
    return <div className="text-center">
      <p className="text-[13px] font-medium text-quaternary-label">听发音，选择正确音标</p>
      <button
        type="button"
        onClick={onPlay}
        className="ios-press mx-auto mt-6 flex size-28 flex-col items-center justify-center gap-2 rounded-full border border-accent/20 bg-accent/10 text-accent shadow-[0_12px_40px_rgba(0,122,255,0.14)] transition-all hover:scale-105 hover:bg-accent/15 active:scale-95 dark:border-accent/30 dark:text-[#0a84ff]"
      >
        <Volume2 className="size-10" />
        <AudioWave active={isPlaying} className="text-accent dark:text-[#0a84ff]" />
      </button>
      <p className="mt-3 text-xs text-tertiary-label">点击可重复播放 · {item.definition}</p>
    </div>;
  }

  if (item.challengeType === "PHONETIC_TO_WORD") {
    return <div className="text-center">
      <p className="text-[13px] font-medium text-quaternary-label">看音标，选择对应单词</p>
      <h1 className="mt-7 break-words font-serif text-4xl font-bold tracking-wide text-accent sm:text-5xl dark:text-[#0a84ff]">{item.phonetic}</h1>
      <button
        type="button"
        onClick={onPlay}
        className="ios-press mx-auto mt-5 inline-flex items-center gap-2 rounded-full border border-accent/20 bg-accent/10 px-4 py-2 text-sm font-semibold text-accent transition hover:bg-accent/15 dark:text-[#0a84ff]"
      >
        {isPlaying ? <AudioWave active className="text-accent dark:text-[#0a84ff]" /> : <Volume2 className="size-4" />}
        播放发音
      </button>
    </div>;
  }

  return <div className="text-center">
    <p className="text-[13px] font-medium text-quaternary-label">看单词，选择正确音标</p>
    <h1 className="mt-6 break-words text-4xl font-black tracking-tight sm:text-5xl">{item.term}</h1>
    <p className="mx-auto mt-3 max-w-lg text-sm leading-relaxed text-quaternary-label">{item.definition}</p>
    <button
      type="button"
      onClick={onPlay}
      className="ios-press mx-auto mt-4 inline-flex items-center gap-2 rounded-full border border-accent/20 bg-accent/10 px-4 py-2 text-sm font-semibold text-accent transition hover:bg-accent/15 dark:text-[#0a84ff]"
    >
      {isPlaying ? <AudioWave active className="text-accent dark:text-[#0a84ff]" /> : <Volume2 className="size-4" />}
      播放发音
    </button>
  </div>;
}

export function PhoneticQuestion({
  item,
  wrongChoice,
  correctFeedback,
  audioError,
  onChoose,
  onPlay,
  onSkip,
}: Props) {
  const [isPlaying, setIsPlaying] = useState(false);
  const expected = correctChoice(item);

  const handlePlay = async () => {
    setIsPlaying(true);
    try {
      await onPlay();
    } finally {
      setIsPlaying(false);
    }
  };

  return <div>
    <div className="mb-4 flex flex-wrap justify-center gap-2">
      {item.priority !== "NORMAL" && <Badge tone="red"><Flame className="size-3.5" />重点复习词</Badge>}
      <Badge tone="blue"><Ear className="size-3.5" />{item.phoneticAccent === "US" ? "美式音标" : "英式音标"}</Badge>
    </div>

    <Prompt item={item} onPlay={handlePlay} isPlaying={isPlaying} />
    {audioError && <p className="mt-3 text-center text-xs text-danger">{audioError}</p>}

    <div className="mx-auto mt-8 grid max-w-xl gap-3 sm:grid-cols-2">
      {item.choices.map((choice) => {
        const wrong = wrongChoice === choice;
        const correct = correctFeedback && choice === expected;
        return <button
          key={choice}
          type="button"
          onClick={() => onChoose(choice)}
          disabled={Boolean(wrongChoice) || correctFeedback}
          className={`ios-press flex min-h-20 items-center justify-center rounded-[18px] border px-4 py-4 text-center transition-all ${
            wrong
              ? "animate-soft-shake border-danger bg-danger/10 text-danger-deep shadow-[0_4px_16px_rgba(255,59,48,0.12)]"
              : correct
                ? "border-success bg-success/10 text-success-deep shadow-[0_4px_16px_rgba(52,199,89,0.14)]"
                : "liquid-glass-subtle border-border/80 hover:border-accent/40 hover:shadow-[0_8px_24px_rgba(0,122,255,0.08)]"
          }`}
        >
          {wrong && <XCircle className="mr-2 inline size-4 text-danger" />}
          {correct && <CheckCircle2 className="mr-2 inline size-4 text-success" />}
          <span className={`min-w-0 break-words ${item.challengeType === "PHONETIC_TO_WORD" ? "text-lg font-bold" : "font-serif text-xl font-bold tracking-wide"}`}>{choice}</span>
        </button>;
      })}
    </div>

    {wrongChoice && <p className="mt-4 text-center text-sm font-medium text-danger animate-fade-down">不对，再听一次后重新选择</p>}
    {correctFeedback && <div className="animate-scale-in mx-auto mt-5 max-w-xl rounded-[18px] border border-success/20 bg-success/[0.08] p-4 text-center">
      <p className="text-xs font-semibold uppercase tracking-wide text-success-deep">正确发音</p>
      <p className="mt-2 text-xl font-bold">{item.term} <span className="ml-2 font-serif text-accent">{item.phonetic}</span></p>
      <p className="mt-1 text-sm text-secondary-label">{item.definition}</p>
    </div>}

    {!correctFeedback && <div className="mt-6 flex justify-center"><Button variant="ghost" size="sm" onClick={onSkip} className="text-quaternary-label">不会，跳过此题</Button></div>}
  </div>;
}
