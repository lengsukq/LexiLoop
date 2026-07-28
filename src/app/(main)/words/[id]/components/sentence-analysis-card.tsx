import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { WordDetail } from "../word-detail-types";

export function SentenceAnalysisCard({ word }: { word: WordDetail }) {
  const analysis = word.content.sentenceAnalysis;
  const hasContent = analysis.grammarNotes.length || analysis.keyExpressions.length || analysis.variations.length;
  if (word.entryType !== "SENTENCE" || !hasContent) return null;

  return <Card>
    <CardHeader><CardTitle>句子分析</CardTitle></CardHeader>
    <CardContent className="space-y-5">
      {analysis.grammarNotes.length > 0 && <Section label="语法要点">{analysis.grammarNotes.map((item) => <div key={item} className="rounded-[14px] border border-[#007aff]/10 bg-[#007aff]/[0.06] p-3 text-sm text-[#007aff] dark:text-[#0a84ff]">{item}</div>)}</Section>}
      {analysis.keyExpressions.length > 0 && <Section label="关键表达">{analysis.keyExpressions.map((item) => <div key={item.expression} className="rounded-[14px] border border-white/50 bg-white/40 p-3 dark:border-white/[0.06] dark:bg-white/[0.04]"><b className="break-words text-sm">{item.expression}</b><p className="mt-1 break-words text-sm text-[#6e6e73] dark:text-[#98989d]">{item.meaning}</p>{item.note && <p className="mt-1 break-words text-xs text-[#aeaeb2]">{item.note}</p>}</div>)}</Section>}
      {analysis.variations.length > 0 && <Section label="替换句型">{analysis.variations.map((item) => <div key={item.sentence} className="rounded-[14px] bg-white/40 p-3 dark:bg-white/[0.04]"><p className="break-words text-sm">{item.sentence}</p>{item.translation && <p className="mt-1 break-words text-xs text-[#6e6e73] dark:text-[#98989d]">{item.translation}</p>}</div>)}</Section>}
    </CardContent>
  </Card>;
}

function Section({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p><div className="space-y-2">{children}</div></div>;
}
