import { Loader2, RefreshCw, Sparkles } from "lucide-react";
import { Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { WordDetail } from "../word-detail-types";

export function LearningCard({
  word,
  busy,
  error,
  onGenerate,
}: {
  word: WordDetail;
  busy: boolean;
  error: string;
  onGenerate: () => Promise<void>;
}) {
  const learning = word.content.learning;
  return <Card>
    <CardHeader><CardTitle className="flex items-center gap-2"><Sparkles className="size-5 text-[#af52de]" />AI 学习提示</CardTitle></CardHeader>
    <CardContent className="space-y-4">
      {learning.pronunciationTip && <InfoBlock label="发音提示" text={learning.pronunciationTip} />}
      {learning.mnemonic ? <InfoBlock label="记忆方法" text={learning.mnemonic} /> : <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">记忆方法</p><Button variant="outline" size="sm" onClick={() => void onGenerate()} disabled={busy}>{busy ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}AI 生成趣味助记</Button>{error && <p className="mt-2 text-xs text-[#ff3b30]">{error}</p>}</div>}
      {learning.mnemonic && <div className="flex justify-end"><Button variant="ghost" size="sm" onClick={() => void onGenerate()} disabled={busy}>{busy ? <Loader2 className="size-3 animate-spin" /> : <RefreshCw className="size-3" />}重新生成</Button></div>}
      {learning.commonMistakes.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">常见错误</p><ul className="space-y-2">{learning.commonMistakes.map((item) => <li key={item} className="rounded-[14px] border border-[#ff9500]/10 bg-[#ff9500]/[0.06] p-3 text-sm text-[#c93400] dark:text-[#ff9f0a]">{item}</li>)}</ul></div>}
    </CardContent>
  </Card>;
}

function InfoBlock({ label, text }: { label: string; text: string }) {
  return <div className="rounded-[16px] border border-[#af52de]/10 bg-[#af52de]/[0.06] p-4"><p className="text-xs font-medium uppercase tracking-wide text-[#af52de]">{label}</p><p className="mt-2 break-words text-sm leading-6">{text}</p></div>;
}
