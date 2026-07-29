"use client";

import Link from "next/link";
import { useParams } from "next/navigation";
import { AlertCircle, ArrowLeft, Loader2 } from "lucide-react";
import { buttonClass } from "@/components/ui";
import { DefinitionsCard } from "./components/definitions-card";
import { ExamplesCard } from "./components/examples-card";
import { ExtendedContentCard } from "./components/extended-content-card";
import { LearningCard } from "./components/learning-card";
import { RelatedWordDialog } from "./components/related-word-dialog";
import { SentenceAnalysisCard } from "./components/sentence-analysis-card";
import { WordHeader } from "./components/word-header";
import { WordSidebar } from "./components/word-sidebar";
import { useWordDetail } from "./use-word-detail";

export default function WordDetailPage() {
  const params = useParams<{ id: string }>();
  const detail = useWordDetail(params.id);

  if (!detail.word && !detail.error) {
    return <div className="grid min-h-[70vh] place-items-center"><Loader2 className="size-8 animate-spin text-[#007aff]" /></div>;
  }
  if (!detail.word) {
    return <div className="py-20 text-center">
      <AlertCircle className="mx-auto size-12 text-[#ff3b30]" />
      <h1 className="mt-4 text-xl font-bold">词条加载失败</h1>
      <p className="mt-2 text-sm text-[#6e6e73] dark:text-[#98989d]">{detail.error}</p>
      <Link href="/words" className={`${buttonClass("outline")} mt-6`}><ArrowLeft className="size-4" />返回单词本</Link>
    </div>;
  }

  const word = detail.word;
  return <div className="space-y-6">
    <WordHeader
      word={word}
      selectedAccent={detail.selectedAccent}
      ttsTip={detail.ttsTip}
      translationBusy={detail.translationBusy}
      translationMessage={detail.translationMessage}
      onAccentChange={detail.setSelectedAccent}
      onPlay={() => detail.playText()}
      onInitialize={detail.initialize}
      onRemove={detail.remove}
      onTranslateSummary={detail.translateSummary}
    />

    {detail.error && <div className="rounded-[18px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.08] p-3 text-sm text-[#d70015] dark:text-[#ff453a]">{detail.error}</div>}

    <div className="grid min-w-0 gap-5 lg:grid-cols-[1.4fr_.6fr]">
      <div className="min-w-0 space-y-5">
        <DefinitionsCard
          word={word}
          manualDefinition={detail.manualDefinition}
          saving={detail.saving}
          translationBusy={detail.translationBusy}
          translationMessage={detail.translationMessage}
          onManualDefinitionChange={detail.setManualDefinition}
          onSave={detail.saveManualDefinition}
          onTranslate={detail.translateSummary}
        />
        <ExamplesCard
          word={word}
          translationBusy={detail.translationBusy}
          translationMessage={detail.translationMessage}
          onTranslate={detail.translateExamples}
          onTranslateExample={detail.translateExample}
          onDeleteExample={detail.deleteExample}
          onPlay={detail.playText}
        />
        <SentenceAnalysisCard word={word} />
        <LearningCard word={word} busy={detail.mnemonicBusy} error={detail.mnemonicError} onGenerate={detail.generateMnemonic} />
        <ExtendedContentCard word={word} onRelatedSelect={detail.openRelated} />
      </div>
      <WordSidebar
        word={word}
        note={detail.note}
        saving={detail.saving}
        onNoteChange={detail.setNote}
        onSaveNote={() => detail.patch({ userNote: detail.note || null })}
        onToggleSuspended={() => detail.patch({ isSuspended: !word.isSuspended })}
      />
    </div>

    {detail.relatedSelection && <RelatedWordDialog
      selection={detail.relatedSelection}
      preview={detail.relatedPreview}
      busy={detail.relatedBusy}
      message={detail.relatedMessage}
      onClose={() => detail.setRelatedSelection(null)}
      onAdd={detail.addRelated}
    />}
  </div>;
}
