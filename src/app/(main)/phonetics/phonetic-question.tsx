"use client";

import { CheckCircle2, Ear, Flame, Volume2, XCircle } from "lucide-react";
import { Badge, Button } from "@/components/ui";
import type { PhoneticGameItem } from "./types";

interface Props {
  item: PhoneticGameItem;
  wrongChoice: string | null;
  correctFeedback: boolean;
  audioError: string;
  onChoose: (choice: string) => void;
  onPlay: () => Promise<void> | void;
  onSkip: () => void;
}

function correctChoice(item: PhoneticGameItem): string {
  return item.challengeType === "PHONETIC_TO_WORD" ? item.term : item.phonetic;
}

function Prompt({ item, onPlay }: Pick<Props, "item" | "onPlay">) {
  if (item.challengeType === "SOUND_TO_PHONETIC") {
    return <div className="text-center">
      <p className="text-[13px] font-medium text-[#8e8e93]">听发音，选择正确音标</p>
      <button type="button" onClick={() => void onPlay()} className="ios-press mx-auto mt-6 grid size-28 place-items-center rounded-full bg-[#007aff]/10 text-[#007aff] shadow-[0_12px_40px_rgba(0,122,255,0.14)] dark:text-[#0a84ff]">
        <Volume2 className="size-12" />
      </button>
      <p className="mt-3 text-xs text-[#aeaeb2]">点击可重复播放 · {item.definition}</p>
    </div>;
  }

  if (item.challengeType === "PHONETIC_TO_WORD") {
    return <div className="text-center">
      <p className="text-[13px] font-medium text-[#8e8e93]">看音标，选择对应单词</p>
      <h1 className="mt-7 break-words font-serif text-4xl font-bold tracking-wide text-[#007aff] sm:text-5xl dark:text-[#0a84ff]">{item.phonetic}</h1>
      <button type="button" onClick={() => void onPlay()} className="ios-press mx-auto mt-5 inline-flex items-center gap-2 rounded-full bg-[#007aff]/10 px-4 py-2 text-sm font-semibold text-[#007aff] dark:text-[#0a84ff]"><Volume2 className="size-4" />播放发音</button>
    </div>;
  }

  return <div className="text-center">
    <p className="text-[13px] font-medium text-[#8e8e93]">看单词，选择正确音标</p>
    <h1 className="mt-6 break-words text-4xl font-black tracking-tight sm:text-5xl">{item.term}</h1>
    <p className="mx-auto mt-3 max-w-lg text-sm leading-relaxed text-[#8e8e93]">{item.definition}</p>
    <button type="button" onClick={() => void onPlay()} className="ios-press mx-auto mt-4 inline-flex items-center gap-2 rounded-full bg-[#007aff]/10 px-4 py-2 text-sm font-semibold text-[#007aff] dark:text-[#0a84ff]"><Volume2 className="size-4" />播放发音</button>
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
  const expected = correctChoice(item);
  return <div>
    <div className="mb-4 flex flex-wrap justify-center gap-2">
      {item.priority !== "NORMAL" && <Badge tone="red"><Flame className="size-3.5" />重点复习词</Badge>}
      <Badge tone="blue"><Ear className="size-3.5" />{item.phoneticAccent === "US" ? "美式音标" : "英式音标"}</Badge>
    </div>

    <Prompt item={item} onPlay={onPlay} />
    {audioError && <p className="mt-3 text-center text-xs text-[#ff3b30]">{audioError}</p>}

    <div className="mx-auto mt-8 grid max-w-xl gap-3 sm:grid-cols-2">
      {item.choices.map((choice) => {
        const wrong = wrongChoice === choice;
        const correct = correctFeedback && choice === expected;
        return <button
          key={choice}
          type="button"
          onClick={() => onChoose(choice)}
          disabled={Boolean(wrongChoice) || correctFeedback}
          className={`ios-press min-h-20 rounded-[18px] border px-4 py-4 text-center transition-all ${
            wrong
              ? "border-[#ff3b30] bg-[#ff3b30]/10 text-[#d70015] dark:text-[#ff453a]"
              : correct
                ? "border-[#34c759] bg-[#34c759]/10 text-[#248a3d] dark:text-[#30d158]"
                : "glass-inner border-white/45 hover:border-[#007aff]/35 hover:shadow-[0_8px_28px_rgba(0,122,255,0.1)] dark:border-white/[0.08]"
          }`}
        >
          {wrong && <XCircle className="mr-2 inline size-4" />}
          {correct && <CheckCircle2 className="mr-2 inline size-4" />}
          <span className={item.challengeType === "PHONETIC_TO_WORD" ? "text-lg font-bold" : "font-serif text-xl font-bold tracking-wide"}>{choice}</span>
        </button>;
      })}
    </div>

    {wrongChoice && <p className="mt-4 text-center text-sm font-medium text-[#ff3b30]">不对，再听一次后重新选择</p>}
    {correctFeedback && <div className="animate-scale-in mx-auto mt-5 max-w-xl rounded-[18px] border border-[#34c759]/20 bg-[#34c759]/[0.08] p-4 text-center">
      <p className="text-xs font-semibold uppercase tracking-wide text-[#248a3d] dark:text-[#30d158]">正确发音</p>
      <p className="mt-2 text-xl font-bold">{item.term} <span className="ml-2 font-serif text-[#007aff] dark:text-[#0a84ff]">{item.phonetic}</span></p>
      <p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d]">{item.definition}</p>
    </div>}

    {!correctFeedback && <div className="mt-6 flex justify-center"><Button variant="ghost" size="sm" onClick={onSkip} className="text-[#8e8e93]">不会，跳过此题</Button></div>}
  </div>;
}
