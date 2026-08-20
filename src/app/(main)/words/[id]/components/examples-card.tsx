import { Check, Loader2, Sparkles, Trash2, Volume2 } from "lucide-react";
import { useState } from "react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { WordDetail } from "../word-detail-types";

export function ExamplesCard({
  word,
  translationBusy,
  translationMessage,
  onTranslate,
  onTranslateExample,
  onDeleteExample,
  onPlay,
}: {
  word: WordDetail;
  translationBusy: boolean;
  translationMessage: string;
  onTranslate: () => Promise<void>;
  onTranslateExample: (index: number) => Promise<void>;
  onDeleteExample: (index: number) => Promise<void>;
  onPlay: (text: string) => Promise<void>;
}) {
  const [translatingIndex, setTranslatingIndex] = useState<number | null>(null);
  const [deletingIndex, setDeletingIndex] = useState<number | null>(null);
  if (!word.content.examples.length) return null;
  const missing = word.content.examples.filter((example) => !example.translation?.trim()).length;
  const shouldScroll = word.content.examples.length > 4;

  async function translateOne(index: number) {
    setTranslatingIndex(index);
    try { await onTranslateExample(index); } finally { setTranslatingIndex(null); }
  }

  async function deleteOne(index: number) {
    const sentence = word.content.examples[index]?.sentence;
    if (!sentence || !window.confirm("确定删除这条例句吗？")) return;
    setDeletingIndex(index);
    try { await onDeleteExample(index); } finally { setDeletingIndex(null); }
  }

  return <Card>
    <CardHeader>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div><CardTitle>例句</CardTitle>{missing > 0 && <p className="mt-1 text-xs text-tertiary-label">有 {missing} 条例句还没有中文翻译</p>}</div>
        {missing > 0 && <Button variant="outline" size="sm" onClick={() => void onTranslate()} disabled={translationBusy}>{translationBusy ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}AI 补全翻译</Button>}
      </div>
    </CardHeader>
    {translationMessage && <div className={`mx-4 mb-1 rounded-[12px] px-3 py-2 text-xs sm:mx-5 ${translationMessage.startsWith("已") || translationMessage.startsWith("没有") ? "bg-success/[0.08] text-success-deep" : "bg-danger/[0.07] text-danger-deep"}`}>{translationMessage}</div>}
    <CardContent className="space-y-3">
      {shouldScroll && <div className="flex items-center gap-2 rounded-[13px] bg-accent/[0.06] px-3 py-2 text-xs text-secondary-label"><span className="size-1.5 rounded-full bg-accent" />例句较多，已启用卡片内滚动</div>}
      <div className={shouldScroll ? "max-h-[min(42vh,32rem)] space-y-3 overflow-y-auto pr-1 [scrollbar-color:rgba(0,122,255,0.35)_transparent]" : "space-y-3"}>
        {word.content.examples.map((example, index) => <div key={`${example.sentence}-${index}`} className="rounded-[16px] border-l-4 border-accent/40 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]">
          <div className="flex items-center justify-between gap-3">
            <div className="flex items-center gap-2"><Badge>{example.difficulty ?? "NORMAL"}</Badge>{example.senseId && <span className="text-xs text-tertiary-label">词义 {example.senseId}</span>}</div>
            <div className="flex shrink-0 items-center gap-1.5">
              <button type="button" aria-label="朗读例句" title="朗读例句" onClick={() => void onPlay(example.sentence)} className="ios-press grid size-8 place-items-center rounded-full bg-accent/10 text-accent transition hover:bg-accent/15 dark:text-[#0a84ff]"><Volume2 className="size-4" /></button>
              <button type="button" aria-label="删除例句" title="删除例句" onClick={() => void deleteOne(index)} disabled={deletingIndex !== null || translatingIndex !== null} className="ios-press grid size-8 place-items-center rounded-full bg-danger/[0.08] text-danger-deep transition hover:bg-danger/[0.14] disabled:pointer-events-none disabled:opacity-40 dark:text-danger"><Trash2 className="size-4" /></button>
            </div>
          </div>
          <p className="mt-2 break-words italic leading-7">{example.sentence}</p>
          <div className="mt-1 flex items-start justify-between gap-3">
            {example.translation?.trim() ? <p className="break-words text-sm text-secondary-label">{example.translation}</p> : <p className="text-xs text-tertiary-label">暂未翻译</p>}
            {!example.translation?.trim() && <button type="button" onClick={() => void translateOne(index)} disabled={translatingIndex !== null || deletingIndex !== null || translationBusy} className="ios-press inline-flex shrink-0 items-center gap-1 rounded-full bg-accent/10 px-2.5 py-1 text-xs font-semibold text-accent transition hover:bg-accent/15 disabled:pointer-events-none disabled:opacity-40 dark:text-[#0a84ff]">
              {translatingIndex === index ? <Loader2 className="size-3.5 animate-spin" /> : <Sparkles className="size-3.5" />}翻译
            </button>}
            {example.translation?.trim() && <span className="mt-0.5 inline-flex shrink-0 items-center gap-1 text-[11px] text-[#34a853] dark:text-success"><Check className="size-3.5" />已翻译</span>}
          </div>
        </div>)}
      </div>
    </CardContent>
  </Card>;
}
