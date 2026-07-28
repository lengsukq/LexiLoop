"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import {
  AlertCircle,
  ArrowLeft,
  CalendarClock,
  Check,
  ChevronDown,
  ExternalLink,
  Loader2,
  PauseCircle,
  PlayCircle,
  Plus,
  RefreshCw,
  Save,
  Sparkles,
  Trash2,
  Volume2,
  X,
} from "lucide-react";
import { apiFetch, formatDate } from "@/lib/client-api";
import { waitForAiTask } from "@/lib/ai-task-client";
import type { DictionaryContent, RelatedWordItem } from "@/lib/types";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, Progress, buttonClass } from "@/components/ui";
import { InitializationBadge, MasteryBadge } from "@/components/status-badges";

type RelationType = "SYNONYM" | "ANTONYM" | "WORD_FAMILY" | "CONFUSED_WITH";

interface Detail {
  id: number;
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  sourceLanguageName: string | null;
  targetLanguageName: string | null;
  entryType: string;
  initializationStatus: string;
  contentSource: string;
  masteryLevel: string;
  masteryScore: number;
  isSuspended: boolean;
  userNote: string | null;
  sourceCreatedAt: string | null;
  createdAt: string;
  updatedAt: string;
  content: DictionaryContent;
  reviewCard: null | {
    dueAt: string;
    stability: number;
    difficulty: number;
    elapsedDays: number;
    scheduledDays: number;
    reps: number;
    lapses: number;
    state: number;
    lastReviewAt: string | null;
  };
  wrongWordState: null | {
    active: boolean;
    wrongCount: number;
    hardCount: number;
    consecutiveCorrect: number;
    lastWrongAt: string | null;
    lastCorrectAt: string | null;
    resolvedAt: string | null;
  };
  recentReviews: Array<{
    id: number;
    reviewedAt: string;
    rating: string;
    questionType: string;
    isCorrect: boolean;
    durationMs: number | null;
  }>;
  providerAttempts: Array<{
    providerId: string;
    status: string;
    durationMs: number;
    fieldsReturned: string[];
    errorCode: string | null;
    errorMessage: string | null;
    metadata: {
      model?: string;
      inputTokens?: number | null;
      outputTokens?: number | null;
      qualityScore?: number;
    } | null;
    createdAt: string;
  }>;
}

interface RelatedPreview {
  term: string;
  normalizedTerm: string;
  sourceLanguage: string;
  targetLanguage: string;
  relation: string;
  translation: string | null;
  partOfSpeech: string | null;
  difference: string | null;
  source: string | null;
  existing: null | {
    id: number;
    term: string;
    initializationStatus: string;
    masteryLevel: string;
    masteryScore: number;
  };
}

interface RelatedSelection {
  item: RelatedWordItem;
  relation: RelationType;
}

export default function WordDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const [word, setWord] = useState<Detail | null>(null);
  const [note, setNote] = useState("");
  const [manualDefinition, setManualDefinition] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  const [selectedAccent, setSelectedAccent] = useState<"US" | "UK" | "GENERAL">("US");
  const [ttsTip, setTtsTip] = useState("");
  const [relatedSelection, setRelatedSelection] = useState<RelatedSelection | null>(null);
  const [relatedPreview, setRelatedPreview] = useState<RelatedPreview | null>(null);
  const [relatedBusy, setRelatedBusy] = useState(false);
  const [relatedMessage, setRelatedMessage] = useState("");
  const [mnemonicBusy, setMnemonicBusy] = useState(false);
  const [mnemonicError, setMnemonicError] = useState("");
  const [translationBusy, setTranslationBusy] = useState(false);
  const [translationMessage, setTranslationMessage] = useState("");

  const applyWord = useCallback((data: Detail) => {
    setWord(data);
    setNote(data.userNote ?? "");
    setManualDefinition(data.content.definitions.find((definition) => definition.source === "user" && definition.isUserEdited)?.text ?? "");
  }, []);

  const load = useCallback(async () => {
    try {
      const data = await apiFetch<Detail>(`/api/words/${params.id}`);
      applyWord(data);
      setError("");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "加载失败");
    }
  }, [applyWord, params.id]);

  useEffect(() => {
    const timer = window.setTimeout(() => void load(), 0);
    return () => window.clearTimeout(timer);
  }, [load]);

  async function patch(values: Record<string, unknown>) {
    if (!word) return;
    setSaving(true);
    try {
      const updated = await apiFetch<Detail>(`/api/words/${word.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(values),
      });
      applyWord(updated);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "保存失败");
    } finally {
      setSaving(false);
    }
  }

  async function saveManualDefinition() {
    if (!word) return;
    setSaving(true);
    setError("");
    try {
      const updated = await apiFetch<Detail>(`/api/words/${word.id}/content`, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ definition: manualDefinition }),
      });
      applyWord(updated);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "保存手动释义失败");
    } finally {
      setSaving(false);
    }
  }

  async function initialize(mode: "FILL_MISSING_FIELDS" | "FORCE_OVERWRITE" = "FILL_MISSING_FIELDS") {
    if (!word) return;
    try {
      await apiFetch(`/api/words/${word.id}/initialize`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ mode }),
      });
      await load();
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "创建任务失败");
    }
  }

  async function remove() {
    if (!word || !window.confirm(`确定删除“${word.term}”及全部学习记录吗？`)) return;
    try {
      await apiFetch(`/api/words/${word.id}`, { method: "DELETE" });
      router.push("/words");
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "删除失败");
    }
  }

  async function openRelated(item: RelatedWordItem, relation: RelationType) {
    if (!word) return;
    setRelatedSelection({ item, relation });
    setRelatedPreview(null);
    setRelatedMessage("");
    setRelatedBusy(true);
    try {
      setRelatedPreview(await apiFetch<RelatedPreview>(`/api/words/${word.id}/related?term=${encodeURIComponent(item.word)}`));
    } catch (reason) {
      setRelatedMessage(reason instanceof Error ? reason.message : "读取关联词状态失败");
    } finally {
      setRelatedBusy(false);
    }
  }

  async function addRelated() {
    if (!word || !relatedSelection) return;
    setRelatedBusy(true);
    setRelatedMessage("");
    try {
      const result = await apiFetch<{
        wordId: number;
        term: string;
        created: boolean;
        queued: boolean;
        initializationStatus: string;
      }>(`/api/words/${word.id}/related`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ term: relatedSelection.item.word, relation: relatedSelection.relation }),
      });
      setRelatedPreview((current) => current ? {
        ...current,
        existing: {
          id: result.wordId,
          term: result.term,
          initializationStatus: result.initializationStatus,
          masteryLevel: "NEW",
          masteryScore: 0,
        },
      } : current);
      setRelatedMessage(result.created
        ? `“${result.term}”已加入词库并进入初始化队列。`
        : result.queued
          ? `“${result.term}”已重新加入初始化队列。`
          : `“${result.term}”已经在词库中。`);
    } catch (reason) {
      setRelatedMessage(reason instanceof Error ? reason.message : "加入关联词失败");
    } finally {
      setRelatedBusy(false);
    }
  }

  async function playText(text = word?.term) {
    if (!text) return;
    setTtsTip("");
    try {
      const response = await fetch(`/api/tts?word=${encodeURIComponent(text)}&accent=${encodeURIComponent(selectedAccent)}`);
      if (!response.ok) throw new Error("TTS 请求失败");
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      audio.playbackRate = 1;
      audio.addEventListener("ended", () => URL.revokeObjectURL(url), { once: true });
      await audio.play();
    } catch {
      setTtsTip("Edge TTS 发音失败，请检查网络。");
    }
  }

  async function generateMnemonic() {
    if (!word) return;
    setMnemonicBusy(true);
    setMnemonicError("");
    setError("");
    try {
      const task = await apiFetch<{ jobId: number }>(`/api/words/${word.id}/mnemonic`, { method: "POST" });
      await waitForAiTask(task.jobId);
      await load();
    } catch (reason) {
      setMnemonicError(reason instanceof Error ? reason.message : "生成失败");
    } finally {
      setMnemonicBusy(false);
    }
  }

  async function translateExamples() {
    if (!word) return;
    setTranslationBusy(true);
    setTranslationMessage("");
    setError("");
    try {
      const task = await apiFetch<{ jobId: number }>(`/api/words/${word.id}/example-translations`, { method: "POST" });
      await waitForAiTask(task.jobId);
      setTranslationMessage("已补全缺失的中文翻译。");
      await load();
    } catch (reason) {
      setTranslationMessage(reason instanceof Error ? reason.message : "补全例句翻译失败");
    } finally {
      setTranslationBusy(false);
    }
  }

  async function translateSummary() {
    if (!word) return;
    setTranslationBusy(true);
    setTranslationMessage("");
    setError("");
    try {
      const task = await apiFetch<{ jobId: number }>(`/api/words/${word.id}/summary-translation`, { method: "POST" });
      await waitForAiTask(task.jobId);
      setTranslationMessage("已补全词条中文释义。");
      await load();
    } catch (reason) {
      setTranslationMessage(reason instanceof Error ? reason.message : "补全中文释义失败");
    } finally {
      setTranslationBusy(false);
    }
  }

  if (!word && !error) {
    return <div className="grid min-h-[70vh] place-items-center"><Loader2 className="size-8 animate-spin text-[#007aff]" /></div>;
  }

  if (!word) {
    return <div className="py-20 text-center">
      <AlertCircle className="mx-auto size-12 text-[#ff3b30]" />
      <h1 className="mt-4 text-xl font-bold">词条加载失败</h1>
      <p className="mt-2 text-sm text-[#6e6e73] dark:text-[#98989d]">{error}</p>
      <Link href="/words" className={`${buttonClass("outline")} mt-6`}><ArrowLeft className="size-4" />返回单词本</Link>
    </div>;
  }

  const targetDefinitions = word.content.definitions.filter((item) => item.language === word.targetLanguage);
  const definitions = targetDefinitions.length ? targetDefinitions : word.content.definitions;
  const hasLearningContent = Boolean(
    word.content.learning.mnemonic
    || word.content.learning.pronunciationTip
    || word.content.learning.commonMistakes.length,
  ) || !word.content.learning.mnemonic; // show card when mnemonic is missing so user can generate one
  const hasExtendedContent = Boolean(
    word.content.forms.length
    || word.content.phrases.length
    || word.content.synonyms.length
    || word.content.antonyms.length
    || word.content.wordFamily.length
    || word.content.confusedWords.length
    || word.content.roots.length
    || word.content.affixes.length
    || word.content.tags.length,
  );
  const missingExampleTranslations = word.content.examples.filter((example) => !example.translation?.trim()).length;
  const missingSummaryTranslation = Boolean(word.content.summary.shortDefinition?.trim()) && !word.content.summary.translation?.trim();

  return <div className="space-y-6">
    <div className="flex flex-wrap items-center justify-between gap-3">
      <Link href="/words" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回单词本</Link>
      <div className="flex flex-wrap gap-2">
        <Button variant="outline" size="sm" onClick={() => void initialize()}><Sparkles className="size-4" />补全缺失内容</Button>
        <Button variant="ghost" size="sm" onClick={() => { if (window.confirm("重新生成会再次调用 AI，但会保留手动释义和例句。确定继续吗？")) void initialize("FORCE_OVERWRITE"); }}><RefreshCw className="size-4" />重新生成</Button>
        <Button variant="danger" size="sm" onClick={() => void remove()}><Trash2 className="size-4" />删除</Button>
      </div>
    </div>

    <Card className="overflow-hidden">
      <div className="bg-gradient-to-br from-[#007aff] to-[#5856d6] p-5 text-white shadow-[0_16px_48px_rgba(0,122,255,0.25)] sm:p-8">
        <div className="flex flex-col gap-5 sm:flex-row sm:items-start sm:justify-between">
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap gap-2">
              <InitializationBadge status={word.initializationStatus} onGradient />
              <MasteryBadge level={word.masteryLevel} onGradient />
              {word.content.summary.cefrLevel && <Badge tone="glass">CEFR {word.content.summary.cefrLevel}</Badge>}
              {word.contentSource === "AI_ONLY" && <Badge tone="glass">纯 AI 生成</Badge>}
              {word.contentSource === "DICTIONARY_ONLY" && <Badge tone="glass">词典</Badge>}
              {word.wrongWordState?.active && <Badge tone="glass">活跃错词</Badge>}
            </div>
            <h1 className="mt-4 break-words text-3xl font-bold sm:mt-5 sm:text-4xl lg:text-5xl">{word.term}</h1>
            {word.content.summary.translation && <p className="mt-2 text-lg font-medium text-white/95 sm:mt-3 sm:text-xl">{word.content.summary.translation}</p>}
            {word.content.summary.shortDefinition && <p className="mt-2 max-w-2xl text-sm leading-6 text-white/80 break-words">{word.content.summary.shortDefinition}</p>}
            {missingSummaryTranslation && <div className="mt-3 flex max-w-2xl flex-wrap items-center gap-2 rounded-xl border border-white/15 bg-black/10 px-3 py-2 text-xs text-white/80 backdrop-blur-sm">
              <span>暂无中文释义</span>
              <button type="button" onClick={() => void translateSummary()} disabled={translationBusy} className="inline-flex items-center gap-1.5 rounded-lg bg-white/15 px-2.5 py-1 font-medium text-white transition hover:bg-white/25 disabled:cursor-wait disabled:opacity-70">
                {translationBusy ? <Loader2 className="size-3.5 animate-spin" /> : <Sparkles className="size-3.5" />}AI 翻译释义
              </button>
            </div>}
            {translationMessage && missingSummaryTranslation && <p className={`mt-2 max-w-2xl text-xs ${translationMessage.startsWith("已") ? "text-emerald-100" : "text-amber-200"}`}>{translationMessage}</p>}
            <p className="mt-3 text-sm text-white/70">{word.sourceLanguageName ?? word.sourceLanguage} → {word.targetLanguageName ?? word.targetLanguage} · {word.entryType === "WORD" ? "单词" : word.entryType === "SENTENCE" ? "句子" : "短语"}</p>
            <div className="mt-4 flex flex-wrap items-center gap-2">
              <div className="flex overflow-hidden rounded-lg border border-white/25">
                {(["US", "UK", "GENERAL"] as const).map((accent) => <button key={accent} type="button" onClick={() => setSelectedAccent(accent)} className={`px-2.5 py-1 text-xs font-medium transition ${selectedAccent === accent ? "bg-white/30 text-white" : "text-white/70 hover:bg-white/10"}`}>{accent === "US" ? "美" : accent === "UK" ? "英" : "通用"}</button>)}
              </div>
              <button type="button" className="inline-flex items-center gap-2 rounded-full bg-white/15 px-4 py-2 text-sm transition hover:bg-white/25" onClick={() => void playText()}><Volume2 className="size-4" />播放发音</button>
              {ttsTip && <p className="w-full text-xs text-amber-300">{ttsTip}</p>}
            </div>
          </div>
          <div className="shrink-0 self-start rounded-3xl bg-white/15 p-5 text-center shadow-[0_8px_32px_rgba(0,0,0,0.1)] backdrop-blur-xl sm:self-auto">
            <p className="text-4xl font-bold">{word.masteryScore}</p>
            <p className="text-xs text-white/70">熟练度</p>
            <Progress value={word.masteryScore} className="mt-3 w-28 bg-white/20 [&>div]:bg-white" />
          </div>
        </div>
      </div>
    </Card>

    {error && <div className="rounded-[18px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.08] p-3 text-sm text-[#d70015] shadow-[0_8px_32px_rgba(255,59,48,0.08)] backdrop-blur-xl dark:text-[#ff453a]">{error}</div>}

    <div className="grid gap-5 lg:grid-cols-[1.4fr_.6fr] min-w-0">
      <div className="space-y-5 min-w-0">
        <Card>
          <CardHeader><CardTitle>释义</CardTitle></CardHeader>
          <CardContent>
            {definitions.length ? <div className="space-y-3">{definitions.map((definition, index) => <div key={`${definition.source}-${definition.senseId ?? index}-${definition.text}`} className="rounded-[16px] border border-white/50 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
              <div className="flex flex-wrap gap-2">
                <Badge>{definition.partOfSpeech || "释义"}</Badge>
                {definition.register && <Badge tone="amber">{definition.register}</Badge>}
                <Badge tone={definition.source === "user" ? "purple" : definition.source.startsWith("ai:") ? "green" : "blue"}>{definition.source === "user" ? "我的释义" : definition.source.startsWith("ai:") ? "AI" : definition.source}</Badge>
              </div>
              <p className="mt-2 leading-7 break-words">{definition.text}</p>              {definition.usageNote && <p className="mt-2 text-xs text-[#6e6e73] dark:text-[#98989d]">用法：{definition.usageNote}</p>}
            </div>)}</div> : <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">尚无释义。可以等待 AI 初始化，或直接填写手动释义继续学习。</p>}
            <div className="mt-5 border-t border-black/[0.06] pt-5 dark:border-white/[0.08]">
              <label className="text-sm font-medium">手动释义</label>
              <textarea className="mt-2 min-h-24 w-full rounded-[14px] border border-black/[0.06] bg-white/60 p-3 text-sm shadow-[inset_0_1px_3px_rgba(0,0,0,0.03)] outline-none backdrop-blur-sm transition focus:border-[#007aff]/40 focus:shadow-[0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08] dark:bg-white/[0.04]" value={manualDefinition} onChange={(event) => setManualDefinition(event.target.value)} placeholder="例如：棉花；棉布。保存后即使 AI 服务暂时失败，该词也可以进入学习。" />
              <div className="mt-3 flex flex-wrap items-center justify-between gap-3">
                <p className="text-xs text-[#aeaeb2]">AI 强制刷新时不会覆盖你的手动释义。</p>
                <Button variant="outline" onClick={() => void saveManualDefinition()} disabled={saving}>{saving ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}保存释义</Button>
              </div>
            </div>
          </CardContent>
        </Card>

        {word.content.examples.length > 0 && <Card>
          <CardHeader><div className="flex flex-wrap items-center justify-between gap-3"><div><CardTitle>例句</CardTitle>{missingExampleTranslations > 0 && <p className="mt-1 text-xs text-[#aeaeb2]">有 {missingExampleTranslations} 条例句还没有中文翻译</p>}</div>{missingExampleTranslations > 0 && <Button variant="outline" size="sm" onClick={() => void translateExamples()} disabled={translationBusy}>{translationBusy ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}AI 补全翻译</Button>}</div></CardHeader>
          {translationMessage && <div className={`mx-4 mb-1 rounded-[12px] px-3 py-2 text-xs sm:mx-5 ${translationMessage.startsWith("已") || translationMessage.startsWith("没有") ? "bg-[#34c759]/[0.08] text-[#248a3d] dark:text-[#30d158]" : "bg-[#ff3b30]/[0.07] text-[#d70015] dark:text-[#ff453a]"}`}>{translationMessage}</div>}
          <CardContent className="space-y-3">{word.content.examples.map((example, index) => <div key={`${example.sentence}-${index}`} className="rounded-[16px] border-l-4 border-[#007aff]/40 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]">
            <div className="flex items-center justify-between gap-3"><div className="flex items-center gap-2"><Badge>{example.difficulty ?? "NORMAL"}</Badge>{example.senseId && <span className="text-xs text-[#aeaeb2]">词义 {example.senseId}</span>}</div><button type="button" aria-label="朗读例句" title="朗读例句" onClick={() => void playText(example.sentence)} className="ios-press grid size-8 shrink-0 place-items-center rounded-full bg-[#007aff]/10 text-[#007aff] transition hover:bg-[#007aff]/15 dark:text-[#0a84ff]"><Volume2 className="size-4" /></button></div>
            <p className="mt-2 italic leading-7 break-words">{example.sentence}</p>
            {example.translation ? <p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d] break-words">{example.translation}</p> : <p className="mt-2 text-xs text-[#aeaeb2]">暂未翻译</p>}
          </div>)}</CardContent>
        </Card>}

        {word.entryType === "SENTENCE" && (word.content.sentenceAnalysis.grammarNotes.length > 0 || word.content.sentenceAnalysis.keyExpressions.length > 0 || word.content.sentenceAnalysis.variations.length > 0) && <Card>
          <CardHeader><CardTitle>句子分析</CardTitle></CardHeader>
          <CardContent className="space-y-5">
            {word.content.sentenceAnalysis.grammarNotes.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">语法要点</p><ul className="space-y-2">{word.content.sentenceAnalysis.grammarNotes.map((item) => <li key={item} className="rounded-[14px] border border-[#007aff]/10 bg-[#007aff]/[0.06] p-3 text-sm break-words text-[#007aff] shadow-[0_4px_12px_rgba(0,122,255,0.04)] backdrop-blur-sm dark:text-[#0a84ff]">{item}</li>)}</ul></div>}
            {word.content.sentenceAnalysis.keyExpressions.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">关键表达</p><div className="space-y-2">{word.content.sentenceAnalysis.keyExpressions.map((item) => <div key={item.expression} className="rounded-[14px] border border-white/50 bg-white/40 p-3 shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><b className="text-sm break-words">{item.expression}</b><p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d] break-words">{item.meaning}</p>{item.note && <p className="mt-1 text-xs text-[#aeaeb2] break-words">{item.note}</p>}</div>)}</div></div>}
            {word.content.sentenceAnalysis.variations.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">替换句型</p><div className="space-y-2">{word.content.sentenceAnalysis.variations.map((item) => <div key={item.sentence} className="rounded-[14px] bg-white/40 p-3 shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]"><p className="text-sm break-words">{item.sentence}</p>{item.translation && <p className="mt-1 text-xs text-[#6e6e73] dark:text-[#98989d] break-words">{item.translation}</p>}</div>)}</div></div>}
          </CardContent>
        </Card>}

        {hasLearningContent && <Card>
          <CardHeader><CardTitle className="flex items-center gap-2"><Sparkles className="size-5 text-[#af52de]" />AI 学习提示</CardTitle></CardHeader>
          <CardContent className="space-y-4">
            {word.content.learning.pronunciationTip && <InfoBlock label="发音提示" text={word.content.learning.pronunciationTip} />}
            {word.content.learning.mnemonic && <InfoBlock label="记忆方法" text={word.content.learning.mnemonic} />}
            {!word.content.learning.mnemonic && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">记忆方法</p><Button variant="outline" size="sm" onClick={() => void generateMnemonic()} disabled={mnemonicBusy}>{mnemonicBusy ? <Loader2 className="size-4 animate-spin" /> : <Sparkles className="size-4" />}AI 生成趣味助记</Button>{mnemonicError && <p className="mt-2 text-xs text-[#ff3b30]">{mnemonicError}</p>}</div>}
            {word.content.learning.mnemonic && <div className="flex justify-end"><Button variant="ghost" size="sm" onClick={() => void generateMnemonic()} disabled={mnemonicBusy}>{mnemonicBusy ? <Loader2 className="size-3 animate-spin" /> : <RefreshCw className="size-3" />}重新生成</Button></div>}

            {word.content.learning.commonMistakes.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">常见错误</p><ul className="space-y-2">{word.content.learning.commonMistakes.map((item) => <li key={item} className="rounded-[14px] border border-[#ff9500]/10 bg-[#ff9500]/[0.06] p-3 text-sm break-words text-[#c93400] shadow-[0_4px_12px_rgba(255,149,0,0.04)] backdrop-blur-sm dark:text-[#ff9f0a]">{item}</li>)}</ul></div>}
          </CardContent>
        </Card>}

        {hasExtendedContent && <Card>
          <CardHeader><CardTitle>扩展信息</CardTitle></CardHeader>
          <CardContent className="space-y-5">
            {word.content.forms.length > 0 && <Group label="词形" values={word.content.forms.map((item) => `${item.type}: ${item.value}`)} />}
            {word.content.phrases.length > 0 && <Group label="搭配与短语" values={word.content.phrases.map((item) => `${item.phrase}${item.translation ? ` · ${item.translation}` : ""}`)} />}
            {word.content.synonyms.length > 0 && <RelatedGroup label="近义词" values={word.content.synonyms} relation="SYNONYM" onSelect={openRelated} />}
            {word.content.antonyms.length > 0 && <RelatedGroup label="反义词" values={word.content.antonyms} relation="ANTONYM" onSelect={openRelated} />}
            {word.content.wordFamily.length > 0 && <RelatedGroup label="同根词 / 词族" values={word.content.wordFamily} relation="WORD_FAMILY" onSelect={openRelated} />}
            {word.content.confusedWords.length > 0 && <RelatedGroup label="易混词" values={word.content.confusedWords} relation="CONFUSED_WITH" onSelect={openRelated} />}
            {word.content.roots.length > 0 && <Group label="词根" values={word.content.roots.map((item) => `${item.root}: ${item.meaning}${item.origin ? ` (${item.origin})` : ""}`)} />}
            {word.content.affixes.length > 0 && <Group label="词缀" values={word.content.affixes.map((item) => `${item.type === "PREFIX" ? "前缀" : "后缀"} ${item.value}: ${item.meaning}`)} />}
            {word.content.tags.length > 0 && <Group label="标签" values={word.content.tags} />}
          </CardContent>
        </Card>}

      </div>

      <div className="space-y-5 min-w-0">
        <Card>
          <CardContent className="space-y-4">
            <Stat label="累计复习" value={word.reviewCard?.reps ?? 0} />
            <Stat label="遗忘次数" value={word.reviewCard?.lapses ?? 0} />
            <Stat label="稳定性" value={word.reviewCard ? word.reviewCard.stability.toFixed(1) : "—"} />
            <Stat label="下次到期" value={formatDate(word.reviewCard?.dueAt, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" })} />
            {word.wrongWordState && <div className="rounded-[16px] border border-[#ff3b30]/10 bg-[#ff3b30]/[0.06] p-3 text-sm shadow-[0_4px_16px_rgba(255,59,48,0.05)] backdrop-blur-sm"><p className="font-medium text-[#d70015] dark:text-[#ff453a]">错词记录</p><p className="mt-1 text-xs text-[#ff3b30]/70">错误 {word.wrongWordState.wrongCount} 次 · 困难 {word.wrongWordState.hardCount} 次 · 连续正确 {word.wrongWordState.consecutiveCorrect}</p></div>}
            <Button variant="outline" className="w-full" onClick={() => void patch({ isSuspended: !word.isSuspended })}>{word.isSuspended ? <PlayCircle className="size-4" /> : <PauseCircle className="size-4" />}{word.isSuspended ? "恢复学习" : "暂停学习"}</Button>
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>个人备注</CardTitle></CardHeader>
          <CardContent>
            <textarea className="min-h-36 w-full rounded-[14px] border border-black/[0.06] bg-white/60 p-3 text-sm shadow-[inset_0_1px_3px_rgba(0,0,0,0.03)] outline-none backdrop-blur-sm transition focus:border-[#007aff]/40 focus:shadow-[0_0_0_4px_rgba(0,122,255,0.08)] dark:border-white/[0.08] dark:bg-white/[0.04]" value={note} onChange={(event) => setNote(event.target.value)} placeholder="记录记忆方法、易混淆词或使用场景…" />
            <div className="mt-3 flex justify-end"><Button onClick={() => void patch({ userNote: note || null })} disabled={saving}>{saving ? <Loader2 className="size-4 animate-spin" /> : <Save className="size-4" />}保存备注</Button></div>
          </CardContent>
        </Card>

        <Card>
          <details className="group">
            <summary className="relative z-10 flex cursor-pointer list-none items-center justify-between gap-3 px-4 py-4 text-[15px] font-bold tracking-tight [&::-webkit-details-marker]:hidden sm:px-5 sm:py-5"><span>AI 初始化质量</span><ChevronDown className="size-4 text-[#8e8e93] transition-transform group-open:rotate-180" /></summary>
            <CardContent>{word.providerAttempts.length ? <div className="space-y-3">{word.providerAttempts.slice(0, 6).map((attempt, index) => <div key={`${attempt.providerId}-${attempt.createdAt}-${index}`} className="rounded-[16px] border border-white/50 bg-white/40 p-3 text-sm shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
            <div className="flex items-center justify-between gap-2"><b className="truncate">{attempt.providerId}</b><Badge tone={attempt.status === "SUCCESS" ? "green" : attempt.status === "FAILED" ? "red" : "amber"}>{attempt.status}</Badge></div>
            {attempt.metadata?.qualityScore !== undefined && <p className="mt-2 text-xs text-[#6e6e73] dark:text-[#98989d]">质量分：{attempt.metadata.qualityScore} · Token：{attempt.metadata.inputTokens ?? "?"} + {attempt.metadata.outputTokens ?? "?"}</p>}
            {attempt.errorMessage && <p className="mt-2 text-xs text-[#ff3b30]">{attempt.errorMessage}</p>}
            </div>)}</div> : <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">尚无初始化记录。</p>}</CardContent>
          </details>
        </Card>

        <Card>
          <CardHeader><CardTitle>最近复习</CardTitle></CardHeader>
          <CardContent>{word.recentReviews.length ? <div className="space-y-3">{word.recentReviews.slice(0, 8).map((review) => <div key={review.id} className="flex items-center justify-between text-sm"><span className="flex items-center gap-2">{review.isCorrect ? <Check className="size-4 text-[#34c759]" /> : <AlertCircle className="size-4 text-[#ff3b30]" />}<span>{review.rating}</span></span><span className="text-xs text-[#aeaeb2]">{formatDate(review.reviewedAt, { month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}</span></div>)}</div> : <p className="text-sm text-[#6e6e73] dark:text-[#98989d]">尚无复习记录。</p>}</CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>来源与时间</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm text-[#6e6e73] dark:text-[#98989d]"><p className="flex items-center gap-2"><CalendarClock className="size-4" />导入：{formatDate(word.createdAt)}</p><p>收藏：{formatDate(word.sourceCreatedAt)}</p><p>内容更新：{formatDate(word.updatedAt)}</p></CardContent>
        </Card>
      </div>
    </div>

    {relatedSelection && <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <button type="button" aria-label="关闭关联词提示" className="absolute inset-0 bg-black/30 backdrop-blur-md" onClick={() => setRelatedSelection(null)} />
      <Card className="relative z-10 w-full max-w-md shadow-2xl">
        <CardHeader>
          <div className="flex items-start justify-between gap-4">
            <div><Badge tone="purple">{relationLabel(relatedSelection.relation)}</Badge><CardTitle className="mt-3 text-2xl">{relatedSelection.item.word}</CardTitle>{relatedSelection.item.translation && <p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d]">{relatedSelection.item.translation}</p>}</div>
            <Button variant="ghost" size="sm" onClick={() => setRelatedSelection(null)}><X className="size-4" /></Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {relatedSelection.item.difference && <div className="rounded-[16px] border border-[#af52de]/10 bg-[#af52de]/[0.06] p-3 text-sm leading-6 text-[#8944ab] shadow-[0_4px_12px_rgba(175,82,222,0.04)] backdrop-blur-sm dark:text-[#bf5af2]">{relatedSelection.item.difference}</div>}
          {relatedBusy && !relatedPreview ? <div className="flex items-center justify-center gap-2 py-6 text-sm text-[#6e6e73] dark:text-[#98989d]"><Loader2 className="size-5 animate-spin" />正在检查词库状态…</div> : relatedPreview && <div className="rounded-[16px] border border-white/50 bg-white/40 p-3 text-sm shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]">
            <div className="flex items-center justify-between"><span className="text-[#6e6e73] dark:text-[#98989d]">词库状态</span>{relatedPreview.existing ? <InitializationBadge status={relatedPreview.existing.initializationStatus} /> : <Badge>尚未加入</Badge>}</div>
            <div className="mt-2 flex items-center justify-between"><span className="text-[#6e6e73] dark:text-[#98989d]">语言方向</span><span>{relatedPreview.sourceLanguage} → {relatedPreview.targetLanguage}</span></div>
            {relatedPreview.partOfSpeech && <div className="mt-2 flex items-center justify-between"><span className="text-[#6e6e73] dark:text-[#98989d]">词性</span><span>{relatedPreview.partOfSpeech}</span></div>}
          </div>}
          {relatedMessage && <div className="rounded-[16px] border border-[#34c759]/10 bg-[#34c759]/[0.06] p-3 text-sm text-[#248a3d] shadow-[0_4px_12px_rgba(52,199,89,0.04)] backdrop-blur-sm dark:text-[#30d158]">{relatedMessage}</div>}
          <div className="flex justify-end gap-2">
            {relatedPreview?.existing && <Link href={`/words/${relatedPreview.existing.id}`} className={buttonClass("outline")}><ExternalLink className="size-4" />打开词条</Link>}
            {(!relatedPreview?.existing || !["READY", "PARTIAL"].includes(relatedPreview.existing.initializationStatus)) && <Button onClick={() => void addRelated()} disabled={relatedBusy || !relatedPreview}>{relatedBusy ? <Loader2 className="size-4 animate-spin" /> : <Plus className="size-4" />}{relatedPreview?.existing ? "加入初始化" : "加入词库并初始化"}</Button>}
          </div>
        </CardContent>
      </Card>
    </div>}
  </div>;
}

function Group({ label, values }: { label: string; values: string[] }) {
  return <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p><div className="flex flex-wrap gap-2">{values.map((value) => <Badge key={value}>{value}</Badge>)}</div></div>;
}

function RelatedGroup({ label, values, relation, onSelect }: { label: string; values: RelatedWordItem[]; relation: RelationType; onSelect: (item: RelatedWordItem, relation: RelationType) => void }) {
  return <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p><div className="flex flex-wrap gap-2">{values.map((item) => <button key={`${relation}-${item.word}`} type="button" onClick={() => void onSelect(item, relation)} className="group inline-flex items-center gap-1.5 rounded-full border border-white/50 bg-white/50 px-3 py-1 text-xs font-medium text-[#1c1c1e] shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-sm transition hover:border-[#007aff]/30 hover:bg-[#007aff]/[0.08] hover:text-[#007aff] hover:shadow-[0_4px_16px_rgba(0,122,255,0.1)] dark:border-white/[0.08] dark:bg-white/[0.06] dark:text-[#f5f5f7] dark:hover:text-[#0a84ff]"><span>{item.word}</span><Plus className="size-3 opacity-45 transition group-hover:opacity-100" /></button>)}</div></div>;
}

function InfoBlock({ label, text }: { label: string; text: string }) {
  return <div className="rounded-[16px] border border-[#af52de]/10 bg-[#af52de]/[0.06] p-4 shadow-[0_4px_16px_rgba(175,82,222,0.05)] backdrop-blur-sm"><p className="text-xs font-medium uppercase tracking-wide text-[#af52de]">{label}</p><p className="mt-2 text-sm leading-6 break-words text-[#1c1c1e] dark:text-[#f5f5f7]">{text}</p></div>;
}

function Stat({ label, value }: { label: string; value: string | number }) {
  return <div className="flex items-center justify-between border-b border-black/[0.05] pb-3 text-sm last:border-0 dark:border-white/[0.06]"><span className="text-[#6e6e73] dark:text-[#98989d]">{label}</span><b>{value}</b></div>;
}

function relationLabel(relation: RelationType): string {
  return { SYNONYM: "近义词", ANTONYM: "反义词", WORD_FAMILY: "同根词 / 词族", CONFUSED_WITH: "易混词" }[relation];
}
