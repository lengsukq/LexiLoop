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
import { Badge, Button, Card, Progress, buttonClass } from "@/components/ui";
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

    <Card className="overflow-hidden">
      <div className="bg-gradient-to-br from-[#007aff] to-[#5856d6] p-5 text-white shadow-[0_16px_48px_rgba(0,122,255,0.25)] sm:p-8">
        <div className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0 flex-1">
            <WordBadges word={word} />
            <h1 className="mt-4 break-words text-3xl font-bold sm:mt-5 sm:text-4xl lg:text-5xl">{word.term}</h1>
            {word.content.summary.translation && <p className="mt-2 text-lg font-medium text-white/95 sm:mt-3 sm:text-xl">{word.content.summary.translation}</p>}
            {word.content.summary.shortDefinition && <p className="mt-2 max-w-2xl break-words text-sm leading-6 text-white/80">{word.content.summary.shortDefinition}</p>}
            {missingTranslation && <TranslationAction busy={translationBusy} onTranslate={onTranslateSummary} />}
            {translationMessage && missingTranslation && <p className={`mt-2 max-w-2xl text-xs ${translationMessage.startsWith("已") ? "text-emerald-100" : "text-amber-200"}`}>{translationMessage}</p>}
            <p className="mt-3 text-sm text-white/70">{word.sourceLanguageName ?? word.sourceLanguage} → {word.targetLanguageName ?? word.targetLanguage} · {entryTypeLabel(word.entryType)}</p>
            <PronunciationControls
              accent={selectedAccent}
              phonetic={
                word.content.pronunciations.find((p) => p.accent === selectedAccent)?.phonetic
                ?? word.content.pronunciations.find((p) => p.accent === "UK")?.phonetic
                ?? null
              }
              tip={ttsTip}
              onAccentChange={onAccentChange}
              onPlay={onPlay}
            />
          </div>
          <div className="shrink-0 self-start rounded-3xl bg-white/15 p-5 text-center shadow-[0_8px_32px_rgba(0,0,0,0.1)] backdrop-blur-xl sm:self-auto">
            <p className="text-4xl font-bold">{word.masteryScore}</p>
            <p className="text-xs text-white/70">熟练度</p>
            <Progress value={word.masteryScore} className="mt-3 w-28 bg-white/20 [&>div]:bg-white" />
          </div>
        </div>
      </div>
    </Card>
  </>;
}

function WordBadges({ word }: { word: WordDetail }) {
  return <div className="flex flex-wrap gap-2">
    <InitializationBadge status={word.initializationStatus} onGradient />
    <MasteryBadge level={word.masteryLevel} onGradient />
    {word.content.summary.cefrLevel && <Badge tone="glass">CEFR {word.content.summary.cefrLevel}</Badge>}
    {word.contentSource === "AI_ONLY" && <Badge tone="glass">AI 内容（手动启用）</Badge>}
    {word.contentSource === "MIXED" && <Badge tone="glass">词典 + AI 补充</Badge>}
    {word.contentSource === "DICTIONARY_ONLY" && <Badge tone="glass">词典内容</Badge>}
    {word.wrongWordState?.active && <Badge tone="glass">活跃错词</Badge>}
  </div>;
}

function TranslationAction({ busy, onTranslate }: { busy: boolean; onTranslate: () => Promise<void> }) {
  return <div className="mt-3 flex max-w-2xl flex-wrap items-center gap-2 rounded-xl border border-white/15 bg-black/10 px-3 py-2 text-xs text-white/80 backdrop-blur-sm">
    <span>暂无中文释义</span>
    <button type="button" onClick={() => void onTranslate()} disabled={busy} className="inline-flex items-center gap-1.5 rounded-lg bg-white/15 px-2.5 py-1 font-medium text-white transition hover:bg-white/25 disabled:cursor-wait disabled:opacity-70">
      {busy ? <Loader2 className="size-3.5 animate-spin" /> : <Sparkles className="size-3.5" />}AI 翻译释义
    </button>
  </div>;
}

function PronunciationControls({ accent, phonetic, tip, onAccentChange, onPlay }: {
  accent: "US" | "UK";
  phonetic: string | null;
  tip: string;
  onAccentChange: (accent: "US" | "UK") => void;
  onPlay: () => Promise<void>;
}) {
  return <div className="mt-4 flex flex-wrap items-center gap-2">
    <div className="flex items-center gap-2">
      <div className="flex overflow-hidden rounded-lg border border-white/25">
        {(["US", "UK"] as const).map((value) => <button key={value} type="button" onClick={() => onAccentChange(value)} className={`px-2.5 py-1 text-xs font-medium transition ${accent === value ? "bg-white/30 text-white" : "text-white/70 hover:bg-white/10"}`}>{value === "US" ? "美" : "英"}</button>)}
      </div>
      {phonetic && <span className="text-sm font-medium tracking-wide text-white/90">{phonetic}</span>}
    </div>
    <button type="button" className="inline-flex items-center gap-2 rounded-full bg-white/15 px-4 py-2 text-sm transition hover:bg-white/25" onClick={() => void onPlay()}><Volume2 className="size-4" />播放发音</button>
    {tip && <p className="w-full text-xs text-amber-300">{tip}</p>}
  </div>;
}

function entryTypeLabel(entryType: string): string {
  if (entryType === "WORD") return "单词";
  if (entryType === "SENTENCE") return "句子";
  return "短语";
}
