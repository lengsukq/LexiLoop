import { BrainCircuit, Braces, Languages, Sparkles } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { WordDetail } from "../word-detail-types";

export function SentenceAnalysisCard({ word }: { word: WordDetail }) {
  const analysis = word.content.sentenceAnalysis;
  const hasContent = Boolean(
    analysis.grammarPattern
    || analysis.grammarExplanation
    || analysis.grammarNotes.length
    || analysis.keyExpressions.length
    || analysis.similarExamples.length
    || analysis.variations.length,
  );
  if (word.entryType !== "SENTENCE" || !hasContent) return null;

  return <Card className="border border-[#5856d6]/15 shadow-[0_16px_48px_rgba(88,86,214,0.10)]">
    <CardHeader className="overflow-hidden border-b border-[#5856d6]/10 bg-gradient-to-br from-[#5856d6]/12 via-[#af52de]/8 to-[#007aff]/8 pb-4">
      <div className="flex items-start gap-3">
        <span className="grid size-11 shrink-0 place-items-center rounded-[15px] bg-gradient-to-br from-[#5856d6] to-[#af52de] text-white shadow-[0_8px_22px_rgba(88,86,214,0.28)]">
          <BrainCircuit className="size-5" />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <CardTitle>AI 语法解析</CardTitle>
            <span className="rounded-full bg-[#5856d6]/10 px-2.5 py-1 text-[11px] font-semibold text-[#5856d6] dark:text-[#bf5af2]">AI 生成</span>
          </div>
          <p className="mt-1 text-[13px] leading-relaxed text-[#6e6e73] dark:text-[#98989d]">拆解核心句型，并通过同语法双语例句帮助迁移使用。</p>
        </div>
      </div>
    </CardHeader>

    <CardContent className="space-y-6 pt-5">
      {(analysis.grammarPattern || analysis.grammarExplanation) && <section className="rounded-[18px] border border-[#5856d6]/15 bg-[#5856d6]/[0.055] p-4 sm:p-5">
        <div className="flex items-center gap-2 text-[#5856d6] dark:text-[#bf5af2]"><Braces className="size-4" /><h3 className="text-sm font-semibold">核心语法结构</h3></div>
        {analysis.grammarPattern && <div className="mt-3 overflow-x-auto rounded-[13px] border border-[#5856d6]/10 bg-white/55 px-4 py-3 font-mono text-[14px] font-semibold leading-relaxed text-[#3a368c] dark:bg-white/[0.045] dark:text-[#bf5af2]">{analysis.grammarPattern}</div>}
        {analysis.grammarExplanation && <p className="mt-3 whitespace-pre-line text-[14px] leading-7 text-[#48484a] dark:text-[#aeaeb2]">{analysis.grammarExplanation}</p>}
      </section>}

      {analysis.grammarNotes.length > 0 && <Section label="语法要点" icon={<Sparkles className="size-4" />}>
        <div className="grid gap-2.5">
          {analysis.grammarNotes.map((item, index) => <div key={item} className="flex gap-3 rounded-[15px] border border-[#007aff]/10 bg-[#007aff]/[0.045] p-3.5">
            <span className="grid size-6 shrink-0 place-items-center rounded-full bg-[#007aff]/10 text-xs font-bold text-[#007aff]">{index + 1}</span>
            <p className="min-w-0 break-words text-[14px] leading-6 text-[#3a3a3c] dark:text-[#c7c7cc]">{item}</p>
          </div>)}
        </div>
      </Section>}

      {analysis.keyExpressions.length > 0 && <Section label="关键表达" icon={<Languages className="size-4" />}>
        <div className="grid gap-3 sm:grid-cols-2">
          {analysis.keyExpressions.map((item) => <div key={item.expression} className="rounded-[16px] border border-white/55 bg-white/45 p-4 shadow-[0_5px_18px_rgba(0,0,0,0.035)] dark:border-white/[0.07] dark:bg-white/[0.035]">
            <b className="break-words text-[14px] text-[#1c1c1e] dark:text-white">{item.expression}</b>
            <p className="mt-1.5 break-words text-[13px] leading-6 text-[#6e6e73] dark:text-[#98989d]">{item.meaning}</p>
            {item.note && <p className="mt-2 break-words border-t border-black/[0.05] pt-2 text-xs leading-5 text-[#8e8e93] dark:border-white/[0.06]">{item.note}</p>}
          </div>)}
        </div>
      </Section>}

      {analysis.similarExamples.length > 0 && <Section label="同语法双语例句" icon={<BrainCircuit className="size-4" />} description="更换人物和语境，但保留与原句相同的核心语法结构。">
        <div className="space-y-3">
          {analysis.similarExamples.map((item, index) => <article key={`${item.sentence}-${index}`} className="group rounded-[17px] border border-[#34c759]/12 bg-[#34c759]/[0.045] p-4 transition-shadow hover:shadow-[0_10px_28px_rgba(52,199,89,0.09)]">
            <div className="flex items-start gap-3">
              <span className="grid size-7 shrink-0 place-items-center rounded-[9px] bg-[#34c759]/12 text-xs font-bold text-[#248a3d] dark:text-[#30d158]">{index + 1}</span>
              <div className="min-w-0 flex-1">
                <p className="break-words text-[15px] font-semibold leading-7 text-[#1c1c1e] dark:text-white">{item.sentence}</p>
                <p className="mt-1 break-words text-[14px] leading-6 text-[#6e6e73] dark:text-[#98989d]">{item.translation}</p>
                {item.focus && <p className="mt-2 inline-flex rounded-full bg-[#34c759]/10 px-2.5 py-1 text-[11px] font-medium text-[#248a3d] dark:text-[#30d158]">语法对应：{item.focus}</p>}
              </div>
            </div>
          </article>)}
        </div>
      </Section>}

      {analysis.variations.length > 0 && <Section label="原句自然改写" description="保持原句含义接近，观察同一意思的不同表达方式。">
        <div className="space-y-2.5">
          {analysis.variations.map((item) => <div key={item.sentence} className="rounded-[15px] border border-black/[0.045] bg-black/[0.018] p-3.5 dark:border-white/[0.055] dark:bg-white/[0.025]">
            <p className="break-words text-[14px] font-medium leading-6">{item.sentence}</p>
            {item.translation && <p className="mt-1 break-words text-[13px] leading-6 text-[#6e6e73] dark:text-[#98989d]">{item.translation}</p>}
          </div>)}
        </div>
      </Section>}
    </CardContent>
  </Card>;
}

function Section({ label, icon, description, children }: { label: string; icon?: React.ReactNode; description?: string; children: React.ReactNode }) {
  return <section>
    <div className="mb-2.5 flex items-center gap-2 text-[#3a3a3c] dark:text-[#d1d1d6]">{icon}<h3 className="text-[13px] font-semibold">{label}</h3></div>
    {description && <p className="-mt-1 mb-3 text-xs leading-5 text-[#8e8e93]">{description}</p>}
    {children}
  </section>;
}
