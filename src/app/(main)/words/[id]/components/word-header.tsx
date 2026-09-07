import { useState } from "react";
import Link from "next/link";
import {
  ArrowLeft,
  BookText,
  Loader2,
  Pencil,
  RefreshCw,
  Sparkles,
  Trash2,
  Volume2,
} from "lucide-react";
import { cn } from "@/lib/cn";
import { AudioWave, Badge, Button, Card, Progress, buttonClass } from "@/components/ui";
import { entryTypeLabel } from "@/lib/entry-type-label";
import { InitializationBadge, MasteryBadge } from "@/components/status-badges";
import type { WordDetail } from "../word-detail-types";

export function WordHeader({
  word,
  selectedAccent,
  ttsTip,
  translationBusy,
  translationMessage,
  onAccentChange,
  onPlay,
  onInitialize,
  onYoudaoFetch,
  onEdit,
  onRemove,
  onTranslateSummary,
}: {
  word: WordDetail;
  selectedAccent: "US" | "UK";
  ttsTip: string;
  translationBusy: boolean;
  translationMessage: string;
  onAccentChange: (accent: "US" | "UK") => void;
  onPlay: () => Promise<void>;
  onInitialize: (mode?: "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE") => Promise<void>;
  onYoudaoFetch: () => Promise<void>;
  onEdit: () => void;
  onRemove: () => Promise<void>;
  onTranslateSummary: () => Promise<void>;
}) {
  const missingTranslation = Boolean(word.content.summary.shortDefinition?.trim())
    && !word.content.summary.translation?.trim();

  return <>
    <div className="flex flex-wrap items-center justify-between gap-3">
      <Link href="/words" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回单词本</Link>
      <div className="flex flex-wrap gap-2">
        <Button variant="outline" size="sm" onClick={() => void onInitialize()}><Sparkles className="size-4" />补全缺失内容</Button>
        <Button variant="outline" size="sm" onClick={() => void onYoudaoFetch()}><BookText className="size-4" />有道词典</Button>
        <Button variant="outline" size="sm" onClick={onEdit}><Pencil className="size-4" />编辑</Button>
        <Button variant="ghost" size="sm" onClick={() => {
          if (window.confirm("重新生成会再次调用 AI，但会保留手动释义和例句。确定继续吗？")) {
            void onInitialize("FORCE_OVERWRITE");
          }
        }}><RefreshCw className="size-4" />重新生成</Button>
        <Button variant="danger" size="sm" onClick={() => void onRemove()}><Trash2 className="size-4" />删除</Button>
      </div>
    </div>

    <Card className="liquid-glass-elevated liquid-glass-specular overflow-hidden rounded-[24px] shadow-[0_16px_40px_-12px_rgba(0,122,255,0.08)]">
      <div className="relative overflow-hidden p-5 sm:p-7">
        <div className="pointer-events-none absolute -right-16 -top-16 size-56 rounded-full bg-accent/15 blur-3xl" />
        <div className="pointer-events-none absolute -bottom-12 -left-12 size-40 rounded-full bg-purple/15 blur-2xl" />

        <div className="relative flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0 flex-1">
            <WordBadges word={word} />
            <h1 className="mt-3.5 break-words text-2xl font-bold tracking-tight text-label sm:mt-4 sm:text-3xl lg:text-4xl">{word.term}</h1>
            {word.content.summary.translation && <p className="mt-1.5 text-base font-medium text-label/90 sm:text-lg">{word.content.summary.translation}</p>}
            {word.content.summary.shortDefinition && <p className="mt-1.5 max-w-2xl break-words text-xs leading-relaxed text-secondary-label sm:text-sm">{word.content.summary.shortDefinition}</p>}
            {missingTranslation && <TranslationAction busy={translationBusy} onTranslate={onTranslateSummary} />}
            {translationMessage && missingTranslation && <p className={`mt-1.5 max-w-2xl text-xs ${translationMessage.startsWith("已") ? "text-success font-medium" : "text-warning font-medium"}`}>{translationMessage}</p>}
            <p className="mt-2 text-xs text-tertiary-label">{word.sourceLanguageName ?? word.sourceLanguage} → {word.targetLanguageName ?? word.targetLanguage} · {entryTypeLabel(word.entryType)}</p>
            <PronunciationControls
              word={word}
              selectedAccent={selectedAccent}
              tip={ttsTip}
              onAccentChange={onAccentChange}
              onPlay={onPlay}
            />
          </div>
          <div className="liquid-glass-subtle shrink-0 self-start rounded-[20px] p-4 text-center shadow-xs backdrop-blur-md sm:self-auto sm:p-4.5">
            <p className="num-tabular text-3xl font-bold tracking-tight text-accent sm:text-4xl">{word.masteryScore}</p>
            <p className="text-[11px] text-tertiary-label font-medium">熟练度</p>
            <Progress value={word.masteryScore} className="mt-2.5 w-24" />
          </div>
        </div>
      </div>
    </Card>
  </>;
}

function WordBadges({ word }: { word: WordDetail }) {
  return <div className="flex flex-wrap gap-2">
    <InitializationBadge status={word.initializationStatus} />
    <MasteryBadge level={word.masteryLevel} />
    {word.content.summary.cefrLevel && <Badge tone="blue">CEFR {word.content.summary.cefrLevel}</Badge>}
    {word.contentSource === "AI_ONLY" && <Badge tone="purple">AI 内容</Badge>}
    {word.contentSource === "MIXED" && <Badge tone="blue">词典 + AI 补充</Badge>}
    {word.contentSource === "DICTIONARY_ONLY" && <Badge tone="slate">词典内容</Badge>}
    {word.wrongWordState?.active && <Badge tone="red">活跃错词</Badge>}
  </div>;
}

function TranslationAction({ busy, onTranslate }: { busy: boolean; onTranslate: () => Promise<void> }) {
  return <div className="mt-3 flex max-w-2xl flex-wrap items-center gap-2 rounded-xl border border-black/[0.08] bg-black/[0.03] px-3 py-2 text-xs text-secondary-label backdrop-blur-sm dark:border-white/[0.08] dark:bg-white/[0.04]">
    <span>暂无中文释义</span>
    <button type="button" onClick={() => void onTranslate()} disabled={busy} className="inline-flex items-center gap-1.5 rounded-lg bg-accent px-2.5 py-1 font-medium text-white transition hover:bg-accent/90 disabled:cursor-wait disabled:opacity-70">
      {busy ? <Loader2 className="size-3.5 animate-spin" /> : <Sparkles className="size-3.5" />}AI 翻译释义
    </button>
  </div>;
}

function PronunciationControls({ word, selectedAccent, tip, onAccentChange, onPlay }: {
  word: WordDetail;
  selectedAccent: "US" | "UK";
  tip: string;
  onAccentChange: (accent: "US" | "UK") => void;
  onPlay: () => Promise<void>;
}) {
  const us = word.content.pronunciations.find((p) => p.accent === "US");
  const uk = word.content.pronunciations.find((p) => p.accent === "UK");
  const [playing, setPlaying] = useState(false);

  async function handlePlay() {
    setPlaying(true);
    try {
      await onPlay();
    } finally {
      window.setTimeout(() => setPlaying(false), 900);
    }
  }

  return (
    <div className="mt-4 flex flex-wrap items-center gap-3">
      <div className="flex flex-wrap items-center gap-2">
        {us && (
          <button
            type="button"
            onClick={() => {
              onAccentChange("US");
              void handlePlay();
            }}
            className={cn(
              "ios-press inline-flex items-center gap-2 rounded-full px-3.5 py-1.5 text-xs font-semibold backdrop-blur-md transition-all",
              selectedAccent === "US"
                ? "bg-accent text-white shadow-[0_2px_10px_rgba(0,122,255,0.3)]"
                : "border border-black/[0.08] bg-white/60 text-secondary-label hover:text-label dark:border-white/[0.08] dark:bg-white/[0.05]"
            )}
          >
            {playing && selectedAccent === "US" ? <AudioWave active /> : <Volume2 className="size-3.5" />}
            <span>美 {us.phonetic || ""}</span>
          </button>
        )}
        {uk && (
          <button
            type="button"
            onClick={() => {
              onAccentChange("UK");
              void handlePlay();
            }}
            className={cn(
              "ios-press inline-flex items-center gap-2 rounded-full px-3.5 py-1.5 text-xs font-semibold backdrop-blur-md transition-all",
              selectedAccent === "UK"
                ? "bg-accent text-white shadow-[0_2px_10px_rgba(0,122,255,0.3)]"
                : "border border-black/[0.08] bg-white/60 text-secondary-label hover:text-label dark:border-white/[0.08] dark:bg-white/[0.05]"
            )}
          >
            {playing && selectedAccent === "UK" ? <AudioWave active /> : <Volume2 className="size-3.5" />}
            <span>英 {uk.phonetic || ""}</span>
          </button>
        )}
        {!us && !uk && (
          <button
            type="button"
            onClick={() => void handlePlay()}
            className="ios-press inline-flex items-center gap-2 rounded-full border border-black/[0.08] bg-white/60 px-4 py-1.5 text-xs font-semibold text-label backdrop-blur-md transition hover:bg-white/90 dark:border-white/[0.08] dark:bg-white/[0.05]"
          >
            {playing ? <AudioWave active /> : <Volume2 className="size-3.5" />}
            <span>播放发音</span>
          </button>
        )}
      </div>
      {tip && <p className="w-full text-xs text-warning">{tip}</p>}
    </div>
  );
}
