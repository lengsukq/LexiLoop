"use client";

import { useEffect, useState } from "react";
import { ChevronLeft, ChevronRight, Loader2, Sparkles, Volume2 } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { playCachedTts, playEntryTts } from "@/lib/tts-client";
import type { SummaryItem } from "./game-summary";
import type { AffixItem, LearningContent, RelatedWordItem, RootItem } from "@/lib/types";
import { Button, Dialog } from "./ui";

interface FlashcardDetail {
  id?: number;
  term: string;
  definition: string;
  phonetic?: string;
  roots?: RootItem[];
  affixes?: AffixItem[];
  confusedWords?: RelatedWordItem[];
  learning?: LearningContent;
}

export function GameMistakeFlashcards({
  open,
  onClose,
  mistakes,
}: {
  open: boolean;
  onClose: () => void;
  mistakes: SummaryItem[];
}) {
  const [index, setIndex] = useState(0);
  const [details, setDetails] = useState<Record<string, FlashcardDetail>>({});
  const [aiGenerating, setAiGenerating] = useState(false);
  const [playing, setPlaying] = useState(false);

  const safeIndex = Math.max(0, Math.min(index, mistakes.length - 1));
  const current: SummaryItem | undefined = mistakes[safeIndex];
  const needsFetch = Boolean(current?.wordId && !details[current.term]);
  const loading = needsFetch;

  useEffect(() => {
    if (!open || !current) return;
    void playEntryTts(current.term, "WORD");

    if (current.wordId && !details[current.term]) {
      let isSubscribed = true;
      void apiFetch<FlashcardDetail>(`/api/words/${current.wordId}/mnemonic`)
        .then((res) => {
          if (isSubscribed && res) {
            setDetails((prev) => ({
              ...prev,
              [current.term]: {
                ...current,
                ...res,
              },
            }));
          }
        })
        .catch(() => {});

      return () => {
        isSubscribed = false;
      };
    }
  }, [current, details, open]);

  if (!current) return null;

  const currentDetail: FlashcardDetail = details[current.term] ?? {
    term: current.term,
    definition: current.definition,
    phonetic: current.phonetic,
    id: current.wordId,
  };

  const mnemonic = currentDetail.learning?.mnemonic;
  const roots = currentDetail.roots ?? [];
  const affixes = currentDetail.affixes ?? [];
  const activeWordId = currentDetail.id ?? current.wordId;

  async function generateAiMnemonic() {
    if (!activeWordId || !current) return;
    setAiGenerating(true);
    try {
      const res = await apiFetch<{
        success: boolean;
        mnemonic: string;
        learning: LearningContent;
        roots?: RootItem[];
        affixes?: AffixItem[];
      }>(`/api/words/${activeWordId}/mnemonic`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sync: true }),
      });

      setDetails((prev) => ({
        ...prev,
        [current.term]: {
          ...currentDetail,
          learning: res.learning,
          roots: res.roots?.length ? res.roots : prev[current.term]?.roots,
          affixes: res.affixes?.length ? res.affixes : prev[current.term]?.affixes,
        },
      }));
    } finally {
      setAiGenerating(false);
    }
  }

  async function playAudio() {
    if (!current) return;
    setPlaying(true);
    try {
      await playCachedTts(current.term, "US");
    } finally {
      window.setTimeout(() => setPlaying(false), 700);
    }
  }

  const handleClose = () => {
    setIndex(0);
    onClose();
  };

  return (
    <Dialog open={open} onClose={handleClose} title="本轮错词 30 秒速记闪卡" maxWidth="max-w-md">
      <div className="space-y-4">
        {/* Progress bar and counter */}
        <div className="flex items-center justify-between text-xs text-secondary-label">
          <span className="font-semibold text-accent">错词记忆强化</span>
          <span className="font-mono font-bold">
            {safeIndex + 1} / {mistakes.length}
          </span>
        </div>

        {/* Card Body */}
        <div className="glass-inner rounded-[22px] border border-white/50 bg-white/60 p-6 text-center shadow-[0_12px_36px_rgba(0,0,0,0.06)] dark:border-white/[0.08] dark:bg-white/[0.05]">
          <div className="flex justify-center">
            <button
              type="button"
              onClick={() => void playAudio()}
              className={`ios-press inline-flex items-center gap-2 rounded-full bg-accent/[0.08] px-3.5 py-1.5 text-xs font-semibold text-accent transition hover:bg-accent/15 dark:bg-[#0a84ff]/[0.12] dark:text-[#0a84ff] ${playing ? "scale-105" : ""}`}
            >
              <Volume2 className={`size-4 ${playing ? "animate-pulse" : ""}`} />
              {current.phonetic ? `/${current.phonetic}/` : "播放发音"}
            </button>
          </div>

          <h2 className="mt-3 break-words text-3xl font-black tracking-tight text-label">
            {current.term}
          </h2>

          <div className="mt-2 text-[15px] font-bold leading-relaxed text-secondary-label">
            {current.definition}
          </div>

          {/* Mnemonic Hook */}
          <div className="mt-5 rounded-[16px] border border-warning/20 bg-warning/[0.08] p-3.5 text-left">
            <div className="flex items-center justify-between gap-1 text-[11px] font-bold text-warning-deep">
              <span className="flex items-center gap-1">
                <Sparkles className="size-3.5 text-warning" />
                趣味巧记
              </span>
              {activeWordId && (
                <button
                  type="button"
                  onClick={() => void generateAiMnemonic()}
                  disabled={aiGenerating}
                  className="ios-press inline-flex items-center gap-1 rounded-full bg-warning/15 px-2 py-0.5 text-[10px] font-semibold text-warning-deep hover:bg-warning/25 disabled:opacity-50"
                >
                  {aiGenerating ? <Loader2 className="size-2.5 animate-spin" /> : <Sparkles className="size-2.5" />}
                  {aiGenerating ? "生成中…" : mnemonic ? "换个助记" : "AI 助记"}
                </button>
              )}
            </div>

            {loading ? (
              <p className="mt-1.5 text-xs text-secondary-label">正在提取助记信息…</p>
            ) : mnemonic ? (
              <p className="mt-1.5 text-xs leading-relaxed text-label font-medium">{mnemonic}</p>
            ) : (
              <p className="mt-1.5 text-xs text-secondary-label">暂无预设助记，点击右上角由 AI 立即创作！</p>
            )}
          </div>

          {/* Roots & Affixes */}
          {(roots.length > 0 || affixes.length > 0) && (
            <div className="mt-3 flex flex-wrap justify-center gap-1.5">
              {roots.map((r: RootItem) => (
                <span key={r.root} className="rounded-md bg-accent/[0.08] px-2 py-0.5 text-[11px] font-medium text-accent">
                  词根 {r.root}: {r.meaning}
                </span>
              ))}
              {affixes.map((a: AffixItem) => (
                <span key={`${a.type}-${a.value}`} className="rounded-md bg-purple/[0.08] px-2 py-0.5 text-[11px] font-medium text-purple">
                  {a.type === "PREFIX" ? "前缀" : "后缀"} {a.value}: {a.meaning}
                </span>
              ))}
            </div>
          )}
        </div>

        {/* Carousel controls */}
        <div className="flex items-center justify-between gap-3 pt-2">
          <Button
            variant="outline"
            size="sm"
            disabled={safeIndex === 0}
            onClick={() => setIndex((i) => Math.max(0, i - 1))}
          >
            <ChevronLeft className="size-4" />
            上一个
          </Button>

          {safeIndex < mistakes.length - 1 ? (
            <Button
              size="sm"
              onClick={() => setIndex((i) => Math.min(mistakes.length - 1, i + 1))}
            >
              下一个
              <ChevronRight className="size-4" />
            </Button>
          ) : (
            <Button size="sm" onClick={handleClose}>
              完成速记
            </Button>
          )}
        </div>
      </div>
    </Dialog>
  );
}
