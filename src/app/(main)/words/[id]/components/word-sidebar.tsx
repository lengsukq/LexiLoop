import { AlertCircle, CalendarClock, Check, ChevronDown, Loader2, PauseCircle, PlayCircle, Save } from "lucide-react";
import { formatDate } from "@/lib/client-api";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { WordDetail } from "../word-detail-types";

export function WordSidebar({
  word,
  note,
  saving,
  onNoteChange,
  onSaveNote,
  onToggleSuspended,
}: {
  word: WordDetail;
  note: string;
  saving: boolean;
  onNoteChange: (value: string) => void;
  onSaveNote: () => Promise<void>;
  onToggleSuspended: () => Promise<void>;
}) {
  return <div className="min-w-0 space-y-5">
    <ReviewStatusCard word={word} onToggleSuspended={onToggleSuspended} />
    <Card>
      <CardHeader><CardTitle>个人备注</CardTitle></CardHeader>
      <CardContent>
        <textarea className="min-h-36 w-full rounded-[14px] border border-black/[0.06] bg-white/60 p-3 text-sm outline-none transition focus:border-[#007aff]/40 focus:shadow-[0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08] dark:bg-white/[0.04]" value={note} onChange={(event) => onNoteChange(event.target.value)} placeholder="记录记忆方法、易混淆词或使用场景…" />
        <div className="mt-3 flex justify-end"><Button onClick={() => void onSaveNote()} disabled={saving}>{saving ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}保存备注</Button></div>
      </CardContent>
    </Card>
    <InitializationQualityCard word={word} />
    <RecentReviewsCard word={word} />
    <SourceTimesCard word={word} />
  </div>;
}

function ReviewStatusCard({ word, onToggleSuspended }: { word: WordDetail; onToggleSuspended: () => Promise<void> }) {
  return <Card><CardContent className="space-y-4">
    <Stat label="累计复习" value={word.reviewCard?.reps ?? 0} />
    <Stat label="遗忘次数" value={word.reviewCard?.lapses ?? 0} />
    <Stat label="稳定性" value={word.reviewCard ? word.reviewCard.stability.toFixed(1) : "—"} />
    <Stat label="下次到期" value={formatDate(word.reviewCard?.dueAt, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })} />
    {word.wrongWordState && <div className="rounded-[16px] border border-[#ff3b30]/10 bg-[#ff3b30]/[0.06] p-3 text-sm"><p className="font-medium text-[#d70015] dark:text-[#ff453a]">错词记录</p><p className="mt-1 text-xs text-[#ff3b30]/70">错误 {word.wrongWordState.wrongCount} 次 · 困难 {word.wrongWordState.hardCount} 次 · 连续正确 {word.wrongWordState.consecutiveCorrect}</p></div>}
    <Button variant="outline" className="w-full" onClick={() => void onToggleSuspended()}>{word.isSuspended ? <PlayCircle className="size-4" /> : <PauseCircle className="size-4" />}{word.isSuspended ? "恢复学习" : "暂停学习"}</Button>
  </CardContent></Card>;
}

function InitializationQualityCard({ word }: { word: WordDetail }) {
  return <Card><details className="group"><summary className="relative z-10 flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-4 text-[15px] font-bold tracking-tight [&::-webkit-details-marker]:hidden sm:px-5 sm:py-5"><span>AI 初始化质量</span><ChevronDown className="size-4 text-[#8e8e93] transition-transform group-open:rotate-180" /></summary><CardContent>{word.providerAttempts.length ? <div className="space-y-3">{word.providerAttempts.slice(0, 6).map((attempt, index) => <div key={`${attempt.providerId}-${attempt.createdAt}-${index}`} className="rounded-[16px] border border-white/50 bg-white/40 p-3 text-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><div className="flex items-center justify-between gap-2"><b className="truncate">{attempt.providerId}</b><Badge tone={attempt.status === "SUCCESS" ? "green" : attempt.status === "FAILED" ? "red" : "amber"}>{attempt.status}</Badge></div>{attempt.metadata?.qualityScore !== undefined && <p className="mt-2 text-xs text-[#6e6e73] dark:text-[#98989d]">质量分：{attempt.metadata.qualityScore} · Token：{attempt.metadata.inputTokens ?? "?"} + {attempt.metadata.outputTokens ?? "?"}</p>}{attempt.errorMessage && <p className="mt-2 text-xs text-[#ff3b30]">{attempt.errorMessage}</p>}</div>)}</div> : <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">尚无初始化记录。</p>}</CardContent></details></Card>;
}

function RecentReviewsCard({ word }: { word: WordDetail }) {
  return <Card><CardHeader><CardTitle>最近复习</CardTitle></CardHeader><CardContent>{word.recentReviews.length ? <div className="space-y-3">{word.recentReviews.slice(0, 8).map((review) => <div key={review.id} className="flex items-center justify-between text-sm"><span className="flex items-center gap-2">{review.isCorrect ? <Check className="size-4 text-[#34c759]" /> : <AlertCircle className="size-4 text-[#ff3b30]" />}<span>{review.rating}</span></span><span className="text-xs text-[#aeaeb2]">{formatDate(review.reviewedAt, { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}</span></div>)}</div> : <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">尚无复习记录。</p>}</CardContent></Card>;
}

function SourceTimesCard({ word }: { word: WordDetail }) {
  return <Card><CardHeader><CardTitle>来源与时间</CardTitle></CardHeader><CardContent className="space-y-2 text-sm text-[#6e6e73] dark:text-[#98989d]"><p className="flex items-center gap-2"><CalendarClock className="size-4" />导入：{formatDate(word.createdAt)}</p><p>收藏：{formatDate(word.sourceCreatedAt)}</p><p>内容更新：{formatDate(word.updatedAt)}</p></CardContent></Card>;
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return <div className="flex items-center justify-between border-b border-black/[0.05] pb-3 text-sm last:border-0 dark:border-white/[0.06]"><span className="text-[#6e6e73] dark:text-[#98989d]">{label}</span><b>{value}</b></div>;
}
