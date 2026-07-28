import { Loader2, Sparkles, Volume2 } from "lucide-react";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { WordDetail } from "../word-detail-types";

export function ExamplesCard({
  word,
  translationBusy,
  translationMessage,
  onTranslate,
  onPlay,
}: {
  word: WordDetail;
  translationBusy: boolean;
  translationMessage: string;
  onTranslate: () => Promise<void>;
  onPlay: (text: string) => Promise<void>;
}) {
  if (!word.content.examples.length) return null;
  const missing = word.content.examples.filter((example) => !example.translation?.trim()).length;

  return <Card>
    <CardHeader>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div><CardTitle>例句</CardTitle>{missing > 0 && <p className="mt-1 text-xs text-[#aeaeb2]">有 {missing} 条例句还没有中文翻译</p>}</div>
        {missing > 0 && <Button variant="outline" size="sm" onClick={() => void onTranslate()} disabled={translationBusy}>{translationBusy ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}AI 补全翻译</Button>}
      </div>
    </CardHeader>
    {translationMessage && <div className={`mx-4 mb-1 rounded-[12px] px-3 py-2 text-xs sm:mx-5 ${translationMessage.startsWith("已") || translationMessage.startsWith("没有") ? "bg-[#34c759]/[0.08] text-[#248a3d] dark:text-[#30d158]" : "bg-[#ff3b30]/[0.07] text-[#d70015] dark:text-[#ff453a]"}`}>{translationMessage}</div>}
    <CardContent className="space-y-3">
      {word.content.examples.map((example, index) => <div key={`${example.sentence}-${index}`} className="rounded-[16px] border-l-4 border-[#007aff]/40 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-2"><Badge>{example.difficulty ?? "NORMAL"}</Badge>{example.senseId && <span className="text-xs text-[#aeaeb2]">词义 {example.senseId}</span>}</div>
          <button type="button" aria-label="朗读例句" title="朗读例句" onClick={() => void onPlay(example.sentence)} className="ios-press grid size-8 shrink-0 place-items-center rounded-full bg-[#007aff]/10 text-[#007aff] transition hover:bg-[#007aff]/15 dark:text-[#0a84ff]"><Volume2 className="size-4" /></button>
        </div>
        <p className="mt-2 break-words italic leading-7">{example.sentence}</p>
        {example.translation ? <p className="mt-1 break-words text-sm text-[#6e6e73] dark:text-[#98989d]">{example.translation}</p> : <p className="mt-2 text-xs text-[#aeaeb2]">暂未翻译</p>}
      </div>)}
    </CardContent>
  </Card>;
}
