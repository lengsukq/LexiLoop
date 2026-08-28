"use client";

import { useEffect, useState } from "react";
import { AlertCircle, BookOpen, Loader2, RefreshCw, Sparkles, Volume2, XCircle } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import { playEntryTts } from "@/lib/tts-client";
import type { AffixItem, DefinitionItem, LearningContent, PronunciationItem, RelatedWordItem, RootItem } from "@/lib/types";
import { Badge, Button, Dialog } from "./ui";

export interface MnemonicSheetWordData {
  id?: number;
  term: string;
  entryType?: string;
  definitions?: DefinitionItem[];
  pronunciations?: PronunciationItem[];
  roots?: RootItem[];
  affixes?: AffixItem[];
  confusedWords?: RelatedWordItem[];
  learning?: LearningContent;
  wrongChoice?: string;
  wrongChoiceDefinition?: string;
}

interface FetchedWordMnemonic {
  id: number;
  term: string;
  entryType: string;
  definitions: DefinitionItem[];
  pronunciations: PronunciationItem[];
  roots: RootItem[];
  affixes: AffixItem[];
  confusedWords: RelatedWordItem[];
  learning: LearningContent;
}

export function WordMnemonicSheet({
  open,
  onClose,
  wordId,
  initialData,
}: {
  open: boolean;
  onClose: () => void;
  wordId?: number;
  initialData?: MnemonicSheetWordData;
}) {
  const [fetched, setFetched] = useState<Partial<FetchedWordMnemonic> | null>(null);
  const [aiGenerating, setAiGenerating] = useState(false);
  const [error, setError] = useState("");
  const [playingAudio, setPlayingAudio] = useState(false);

  const activeWordId = initialData?.id ?? wordId;
  const needsFetch = Boolean(activeWordId && (!initialData?.roots || !initialData?.learning));
  const loading = needsFetch && fetched === null;

  useEffect(() => {
    if (!open || !activeWordId || !needsFetch) return;
    let cancelled = false;
    void apiFetch<FetchedWordMnemonic>(`/api/words/${activeWordId}/mnemonic`)
      .then((res) => {
        if (!cancelled && res) setFetched(res);
      })
      .catch(() => {
        if (!cancelled) setError("获取助记详情失败");
      });
    return () => {
      cancelled = true;
    };
  }, [activeWordId, needsFetch, open]);

  async function generateAiMnemonic() {
    if (!activeWordId) return;
    setAiGenerating(true);
    setError("");
    try {
      const res = await apiFetch<{
        success: boolean;
        mnemonic: string;
        learning: LearningContent;
        roots?: RootItem[];
        affixes?: AffixItem[];
        confusedWords?: RelatedWordItem[];
      }>(`/api/words/${activeWordId}/mnemonic`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ sync: true }),
      });

      setFetched((prev) => ({
        ...(prev ?? {}),
        learning: res.learning,
        roots: res.roots?.length ? res.roots : prev?.roots,
        affixes: res.affixes?.length ? res.affixes : prev?.affixes,
        confusedWords: res.confusedWords?.length ? res.confusedWords : prev?.confusedWords,
      }));
    } catch {
      setError("AI 助记生成失败，请检查网络或 AI 设定");
    } finally {
      setAiGenerating(false);
    }
  }

  const data: MnemonicSheetWordData = {
    ...(initialData ?? { term: "单词详情" }),
    ...(fetched ?? {}),
  };

  async function playTts() {
    if (!data.term) return;
    setPlayingAudio(true);
    try {
      await playEntryTts(data.term, data.entryType ?? "WORD");
    } finally {
      window.setTimeout(() => setPlayingAudio(false), 800);
    }
  }

  const term = data.term ?? "单词详情";
  const defText = (data.definitions ?? [])
    .map((d) => d.text)
    .join("；") || "暂无释义";
  const mnemonic = data.learning?.mnemonic;
  const roots = data.roots ?? [];
  const affixes = data.affixes ?? [];
  const confusedWords = data.confusedWords ?? [];
  const usPhonetic = (data.pronunciations ?? []).find((p) => p.accent === "US")?.phonetic;

  return (
    <Dialog open={open} onClose={onClose} title="错题深度助记与解析" maxWidth="max-w-xl">
      <div className="space-y-3.5">
        {/* Header with Term, Phonetic & Audio */}
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-[16px] border border-accent/15 bg-accent/[0.04] p-3.5">
          <div className="min-w-0 flex-1">
            <div className="flex items-baseline gap-2">
              <h3 className="break-words text-xl font-bold tracking-tight text-label sm:text-2xl">{term}</h3>
              {usPhonetic && <span className="font-mono text-xs text-secondary-label">/{usPhonetic}/</span>}
            </div>
            <p className="mt-1 text-xs font-medium leading-relaxed text-secondary-label sm:text-[13px]">{defText}</p>
          </div>
          <button
            type="button"
            onClick={() => void playTts()}
            className={`ios-press inline-flex items-center gap-1.5 rounded-full bg-accent px-3.5 py-1.5 text-xs font-semibold text-white shadow-xs transition-all hover:bg-accent/90 ${playingAudio ? "scale-105" : ""}`}
          >
            <Volume2 className={`size-3.5 ${playingAudio ? "animate-pulse" : ""}`} />
            朗读
          </button>
        </div>

        {/* Distractor contrast (if user made a wrong choice) */}
        {initialData?.wrongChoice && (
          <div className="rounded-[14px] border border-danger/20 bg-danger/[0.04] p-3">
            <div className="flex items-center gap-1.5 text-xs font-bold text-danger">
              <XCircle className="size-3.5 shrink-0" />
              错选辨析
            </div>
            <div className="mt-1.5 space-y-0.5 text-xs">
              <p className="text-danger-deep">
                ❌ 你选的 <b>{initialData.wrongChoice}</b>
                {initialData.wrongChoiceDefinition ? `：${initialData.wrongChoiceDefinition}` : ""}
              </p>
              <p className="text-success-deep font-semibold">
                ✅ 正确答案 <b>{term}</b>：{defText}
              </p>
            </div>
          </div>
        )}

        {loading ? (
          <div className="py-8 text-center text-secondary-label">
            <Loader2 className="mx-auto size-5 animate-spin text-accent" />
            <p className="mt-2 text-xs">正在加载深度助记库…</p>
          </div>
        ) : (
          <>
            {/* 1. Mnemonic Hook */}
            <div className="rounded-[16px] border border-warning/20 bg-warning/[0.05] p-3.5 shadow-xs">
              <div className="flex items-center justify-between gap-2">
                <span className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-warning-deep">
                  <Sparkles className="size-3.5 text-warning" />
                  趣味联想 / 谐音助记
                </span>
                {activeWordId && (
                  <button
                    type="button"
                    onClick={() => void generateAiMnemonic()}
                    disabled={aiGenerating}
                    className="ios-press inline-flex items-center gap-1 rounded-full bg-warning/15 px-2 py-0.5 text-[10.5px] font-semibold text-warning-deep transition hover:bg-warning/25 disabled:opacity-50"
                  >
                    {aiGenerating ? <Loader2 className="size-3 animate-spin" /> : mnemonic ? <RefreshCw className="size-3" /> : <Sparkles className="size-3" />}
                    {aiGenerating ? "AI 创作中…" : mnemonic ? "换个助记" : "AI 巧记"}
                  </button>
                )}
              </div>

              {mnemonic ? (
                <p className="mt-2 text-[13px] leading-relaxed text-label font-medium whitespace-pre-wrap">{mnemonic}</p>
              ) : (
                <div className="mt-2.5 text-center py-1.5">
                  <p className="text-xs text-secondary-label">暂未生成趣味助记，点击上方按钮让 AI 立即创作！</p>
                </div>
              )}
            </div>

            {/* 2. Roots & Affixes (词根词缀) */}
            {(roots.length > 0 || affixes.length > 0) && (
              <div className="rounded-[16px] border border-accent/15 bg-accent/[0.035] p-3.5">
                <span className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-accent-deep">
                  <BookOpen className="size-3.5 text-accent" />
                  词根词缀构词拆解
                </span>
                <div className="mt-2 flex flex-wrap gap-1.5">
                  {roots.map((root) => (
                    <span
                      key={root.root}
                      className="inline-flex items-center gap-1.5 rounded-[8px] bg-white/70 px-2 py-0.5 text-xs font-semibold text-label shadow-2xs dark:bg-white/[0.08]"
                    >
                      <span className="font-mono text-accent">词根 {root.root}</span>
                      <span className="text-secondary-label font-normal">({root.meaning}{root.origin ? ` · ${root.origin}` : ""})</span>
                    </span>
                  ))}
                  {affixes.map((affix) => (
                    <span
                      key={`${affix.type}-${affix.value}`}
                      className="inline-flex items-center gap-1.5 rounded-[8px] bg-white/70 px-2 py-0.5 text-xs font-semibold text-label shadow-2xs dark:bg-white/[0.08]"
                    >
                      <span className="font-mono text-purple">{affix.type === "PREFIX" ? "前缀" : "后缀"} {affix.value}</span>
                      <span className="text-secondary-label font-normal">({affix.meaning})</span>
                    </span>
                  ))}
                </div>
              </div>
            )}

            {/* 3. Confused Words (易混词辨析) */}
            {confusedWords.length > 0 && (
              <div className="rounded-[16px] border border-black/[0.06] bg-black/[0.02] p-3.5 dark:border-white/[0.06] dark:bg-white/[0.03]">
                <span className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-secondary-label">
                  ⚠️ 易混词与同根词辨析
                </span>
                <div className="mt-2 space-y-1.5">
                  {confusedWords.map((cw) => (
                    <div key={cw.word} className="flex items-baseline justify-between gap-2 text-xs">
                      <b className="font-semibold text-label">{cw.word}</b>
                      <span className="text-secondary-label text-right">{cw.translation || cw.difference || "暂无释义"}</span>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}

        {error && (
          <div className="flex items-center gap-2 rounded-[14px] bg-danger/[0.08] p-3 text-xs text-danger">
            <AlertCircle className="size-4 shrink-0" />
            {error}
          </div>
        )}

        <div className="flex justify-end pt-2">
          <Button variant="outline" size="sm" onClick={onClose}>
            完成复盘
          </Button>
        </div>
      </div>
    </Dialog>
  );
}
