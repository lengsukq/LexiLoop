"use client";

import Link from "next/link";
import { errorMessage } from "@/lib/format";
import { useState } from "react";
import { AlertCircle, ArrowRight, BookPlus, CheckCircle2, ChevronDown, ChevronUp, ListChecks, Loader2, RefreshCw, Sparkles } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import type { EntryType, ManualContentPreview } from "@/lib/types";
import { Alert, Badge, Button, Card, CardContent, CardHeader, CardTitle, Kbd, Select, buttonClass } from "@/components/ui";

type TypeChoice = "AUTO" | EntryType;

const MAX_ROWS = 100;
const MAX_CHARS_PER_LINE = 1200;
const MAX_TOTAL_CHARS = 24000;
const PREVIEW_CONCURRENCY = 5;

async function runWithConcurrency<T>(items: T[], limit: number, task: (item: T, index: number) => Promise<void>): Promise<void> {
  let nextIndex = 0;
  const workerCount = Math.min(limit, items.length);
  const workers = Array.from({ length: workerCount }, async () => {
    while (nextIndex < items.length) {
      const index = nextIndex;
      nextIndex += 1;
      await task(items[index]!, index);
    }
  });
  await Promise.all(workers);
}

const TYPE_META: Record<EntryType, { label: string; description: string }> = {
  WORD: { label: "单词", description: "词条释义、音标、词形与短语搭配" },
  PHRASE: { label: "短语", description: "短语释义、固定搭配与例句" },
  SENTENCE: { label: "句子", description: "翻译、关键词解析与例句" },
};

interface BatchRow {
  term: string;
  preview: ManualContentPreview | null;
  error: string;
  confirmedWordId: number | null;
}

export function ManualTab() {
  const [text, setText] = useState("");
  const [typeChoice, setTypeChoice] = useState<TypeChoice>("AUTO");
  const [sourceLanguage, setSourceLanguage] = useState("en");
  const [targetLanguage, setTargetLanguage] = useState("zh-CN");
  const [batch, setBatch] = useState<BatchRow[] | null>(null);
  const [busy, setBusy] = useState<"preview" | "confirm" | "">("");
  const [error, setError] = useState("");
  const [expandedIndex, setExpandedIndex] = useState<number | null>(null);
  const [previewDone, setPreviewDone] = useState(0);

  const lines = text.split("\n").map((line) => line.trim()).filter(Boolean);
  const lineCount = lines.length;

  async function generatePreviews() {
    if (lineCount > MAX_ROWS) {
      setError(`一次最多支持 ${MAX_ROWS} 行，请分多次添加。`);
      return;
    }
    const overlong = lines.find((line) => line.length > MAX_CHARS_PER_LINE);
    if (overlong) {
      setError(`“${overlong.slice(0, 24)}…”超过单行 ${MAX_CHARS_PER_LINE} 字符限制，请缩短后重试。`);
      return;
    }
    setBatch(lines.map((term) => ({ term, preview: null, error: "", confirmedWordId: null })));
    setBusy("preview");
    setError("");
    setExpandedIndex(null);
    setPreviewDone(0);
    await runWithConcurrency(lines, PREVIEW_CONCURRENCY, async (term, index) => {
      try {
        const data = await apiFetch<ManualContentPreview>("/api/manual/preview", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            text: term,
            sourceLanguage,
            targetLanguage,
            ...(typeChoice === "AUTO" ? {} : { contentType: typeChoice }),
          }),
        });
        setBatch((previous) => previous?.map((row, i) => i === index ? { ...row, preview: data } : row) ?? null);
      } catch (reason) {
        setBatch((previous) => previous?.map((row, i) => i === index ? { ...row, error: errorMessage(reason, "生成预览失败") } : row) ?? null);
      } finally {
        setPreviewDone((count) => count + 1);
      }
    });
    setBusy("");
    setExpandedIndex(lines.length === 1 ? 0 : null);
  }

  async function confirmRow(index: number) {
    const row = batch?.[index];
    if (!row?.preview || row.confirmedWordId !== null || busy) return;
    setBusy("confirm");
    setError("");
    try {
      const result = await apiFetch<{ wordId: number }>("/api/manual/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ previewToken: row.preview.previewToken }),
      });
      setBatch((previous) => previous?.map((item, i) => i === index ? { ...item, confirmedWordId: result.wordId } : item) ?? null);
    } catch (reason) {
      setError(`确认“${row.term}”失败：${errorMessage(reason, "确认添加失败")}`);
    } finally {
      setBusy("");
    }
  }

  async function confirmAll() {
    if (!batch || busy) return;
    setBusy("confirm");
    setError("");
    for (let index = 0; index < batch.length; index++) {
      const row = batch[index];
      if (!row || !row.preview || row.confirmedWordId !== null) continue;
      try {
        const result = await apiFetch<{ wordId: number }>("/api/manual/confirm", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ previewToken: row.preview.previewToken }),
        });
        setBatch((previous) => previous?.map((item, i) => i === index ? { ...item, confirmedWordId: result.wordId } : item) ?? null);
      } catch (reason) {
        setError(`确认“${row.term}”失败：${errorMessage(reason, "确认添加失败")}`);
      }
    }
    setBusy("");
  }

  function reset() {
    setBatch(null);
    setExpandedIndex(null);
    setError("");
  }

  const successRows = batch?.filter((row) => row.preview) ?? [];
  const pendingRows = successRows.filter((row) => row.confirmedWordId === null);
  const allConfirmed = successRows.length > 0 && pendingRows.length === 0;

  return <div className="space-y-6">
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-3">
          <CardTitle className="flex items-center gap-2"><BookPlus className="size-5 text-accent" />输入学习内容</CardTitle>
          <div className="flex flex-wrap items-center gap-1.5">
            <span className="text-xs text-secondary-label">快捷填入：</span>
            <button
              type="button"
              onClick={() => { setText("serendipity\nresilient\nmeticulous"); if (batch) reset(); }}
              className="ios-press rounded-full bg-black/[0.04] px-2.5 py-1 text-xs font-medium text-secondary-label hover:bg-accent/10 hover:text-accent dark:bg-white/[0.06] dark:hover:bg-white/[0.12]"
            >
              + 单词示例
            </button>
            <button
              type="button"
              onClick={() => { setText("bring up\ntake for granted\ncome across"); if (batch) reset(); }}
              className="ios-press rounded-full bg-black/[0.04] px-2.5 py-1 text-xs font-medium text-secondary-label hover:bg-accent/10 hover:text-accent dark:bg-white/[0.06] dark:hover:bg-white/[0.12]"
            >
              + 短语示例
            </button>
            <button
              type="button"
              onClick={() => { setText("Practice makes perfect.\nAction speaks louder than words."); if (batch) reset(); }}
              className="ios-press rounded-full bg-black/[0.04] px-2.5 py-1 text-xs font-medium text-secondary-label hover:bg-accent/10 hover:text-accent dark:bg-white/[0.06] dark:hover:bg-white/[0.12]"
            >
              + 句子示例
            </button>
          </div>
        </div>
      </CardHeader>
      <CardContent className="space-y-5">
        <textarea
          className="min-h-32 w-full rounded-[16px] border border-black/[0.08] bg-white/70 p-3.5 text-base outline-none transition placeholder:text-tertiary-label focus:border-accent focus:bg-white focus:shadow-[0_4px_16px_rgba(0,122,255,0.08)] dark:border-white/[0.09] dark:bg-white/[0.05]"
          value={text}
          onChange={(event) => { setText(event.target.value); if (batch) reset(); }}
          onKeyDown={(event) => {
            if ((event.metaKey || event.ctrlKey) && event.key === "Enter" && lineCount > 0 && busy === "") {
              event.preventDefault();
              void generatePreviews();
            }
          }}
          placeholder={'每行一个单词/词组/句子，例如：\nabandon\nbreak down\nI have been working here for five years.'}
          maxLength={MAX_TOTAL_CHARS}
        />
        <div className="flex items-center justify-between gap-3 num-tabular">
          <p className="text-xs text-tertiary-label">已输入 {lineCount} 行，最多 {MAX_ROWS} 行。类型、原语言、目标语言会应用到每一行。</p>
          <span className="text-xs font-medium text-tertiary-label">{text.length}/{MAX_TOTAL_CHARS}</span>
        </div>
        <div className="grid gap-3 md:grid-cols-3">
          <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">内容类型</span><Select className="w-full" value={typeChoice} onChange={(event) => setTypeChoice(event.target.value as TypeChoice)}><option value="AUTO">自动判断</option><option value="WORD">单词</option><option value="PHRASE">短语</option><option value="SENTENCE">句子</option></Select></label>
          <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">原语言</span><Select className="w-full" value={sourceLanguage} onChange={(event) => setSourceLanguage(event.target.value)}><option value="en">英语</option><option value="zh-CN">简体中文</option><option value="ja">日语</option><option value="ko">韩语</option><option value="fr">法语</option><option value="de">德语</option><option value="es">西班牙语</option></Select></label>
          <label className="space-y-1.5"><span className="text-xs font-medium text-secondary-label">目标语言</span><Select className="w-full" value={targetLanguage} onChange={(event) => setTargetLanguage(event.target.value)}><option value="zh-CN">简体中文</option><option value="en">英语</option><option value="ja">日语</option><option value="ko">韩语</option><option value="fr">法语</option><option value="de">德语</option><option value="es">西班牙语</option></Select></label>
        </div>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-xs text-tertiary-label">生成预览会先查询有道词典，识别不出短语或句子时自动用腾讯翻译 / AI 兜底，不会创建正式词条。</p>
          <Button size="lg" onClick={() => void generatePreviews()} disabled={lineCount === 0 || busy !== ""}>
            {busy === "preview" ? <Loader2 className="size-4.5 animate-spin" /> : <Sparkles className="size-4.5" />}
            {batch ? "重新生成预览" : "生成预览"}
            <Kbd className="ml-1.5 hidden sm:inline-flex bg-white/20 text-white border-white/30">⌘ Enter</Kbd>
          </Button>
        </div>
      </CardContent>
    </Card>

    {error && <Alert icon={<AlertCircle className="size-4" />}>{error}</Alert>}

    {batch && <div className="space-y-4">
      <Card className="rounded-[22px]">
        <CardHeader>
          <div className="flex flex-wrap items-center justify-between gap-3">
            <div>
              <CardTitle className="flex items-center gap-2"><ListChecks className="size-4.5 text-accent" />批量预览</CardTitle>
              <p className="mt-1 text-xs text-secondary-label">{successRows.length > 0 && <span className="font-semibold text-accent">{successRows.length} 行成功</span>}{successRows.length > 0 && " · "}共 {batch.length} 行，确认后才会写入正式词库</p>
            </div>
            <Button variant="ghost" size="sm" onClick={() => void generatePreviews()} disabled={busy !== ""}>{busy === "preview" ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}重新生成</Button>
          </div>
        </CardHeader>
        <CardContent className="space-y-2.5">
          {busy === "preview" && <div className="flex items-center gap-2.5 rounded-[14px] border border-accent/15 bg-accent/[0.05] p-3 text-xs text-accent dark:text-[#0a84ff]"><Loader2 className="size-4 animate-spin" />正在逐行查询有道词典，请稍候…（{previewDone}/{batch.length}）</div>}
          {batch.map((row, index) => <BatchRowCard key={`${row.term}-${index}`} row={row} index={index} expanded={expandedIndex === index} busy={busy !== ""} onToggle={() => setExpandedIndex(expandedIndex === index ? null : index)} onConfirm={() => void confirmRow(index)} />)}
        </CardContent>
      </Card>

      {allConfirmed ? <Card className="rounded-[22px]"><CardContent className="py-9 text-center"><CheckCircle2 className="mx-auto size-11 text-success" /><h2 className="mt-2.5 text-lg font-bold">已全部加入词库</h2><p className="mt-1 text-xs text-secondary-label">共确认 {successRows.length} 个词条，词典预览内容已经正式保存。</p><div className="mt-4 flex flex-wrap justify-center gap-2.5">{successRows.map((row) => row.confirmedWordId !== null && <Link key={row.confirmedWordId} href={`/words/${row.confirmedWordId}`} className={buttonClass("primary", "sm")}><ArrowRight className="size-3.5" />打开{row.term}</Link>)}<Button variant="outline" size="sm" onClick={() => { setText(""); reset(); }}>继续添加</Button></div></CardContent></Card> : <Card className="rounded-[22px]"><CardContent className="flex flex-col gap-3 pt-4 sm:flex-row sm:items-center sm:justify-between"><div><p className="text-sm font-semibold">确认后才会写入正式词库</p><p className="mt-0.5 text-xs text-secondary-label">确认不会再次查询词典，也可以先逐个展开查看后再确认。</p></div><Button size="lg" onClick={() => void confirmAll()} disabled={pendingRows.length === 0 || busy !== ""}>{busy === "confirm" ? <Loader2 className="size-4.5 animate-spin" /> : <CheckCircle2 className="size-4.5" />}全部确认加入（{pendingRows.length}）</Button></CardContent></Card>}
    </div>}
  </div>;
}

function BatchRowCard({ row, index, expanded, busy, onToggle, onConfirm }: {
  row: BatchRow;
  index: number;
  expanded: boolean;
  busy: boolean;
  onToggle: () => void;
  onConfirm: () => void;
}) {
  return <div className="rounded-[16px] border border-black/[0.07] bg-white/60 p-3.5 shadow-2xs dark:border-white/[0.07] dark:bg-white/[0.04]">
    <div className="flex flex-col gap-2.5 sm:flex-row sm:items-center sm:justify-between">
      <div className="flex min-w-0 items-center gap-2.5">
        <span className="grid size-6 shrink-0 place-items-center rounded-full bg-accent/10 text-xs font-bold text-accent dark:bg-[#0a84ff]/15 dark:text-[#0a84ff]">{index + 1}</span>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-1.5">
            <b className="truncate text-[14.5px] font-semibold">{row.term}</b>
            {row.preview && <Badge>{TYPE_META[row.preview.contentType].label}</Badge>}
            {row.preview?.existingWordId && <Badge tone="amber">已存在</Badge>}
            {row.confirmedWordId !== null && <Badge tone="green">已确认</Badge>}
          </div>
          <p className="mt-1 truncate text-sm text-secondary-label">{row.error || row.preview?.content.summary.translation || "正在生成预览…"}</p>
          {row.error && <p className="mt-1 text-xs text-danger-deep">{row.error}</p>}
        </div>
      </div>
      <div className="flex shrink-0 items-center gap-2">
        {row.preview && row.confirmedWordId === null && <Button size="sm" variant="outline" onClick={onConfirm} disabled={busy}><CheckCircle2 className="size-4" />确认</Button>}
        {row.confirmedWordId !== null && <Link href={`/words/${row.confirmedWordId}`} className={buttonClass("outline", "sm")}><ArrowRight className="size-4" />打开词条</Link>}
        {row.preview && <Button size="sm" variant="ghost" onClick={onToggle}>{expanded ? <ChevronUp className="size-4" /> : <ChevronDown className="size-4" />}{expanded ? "收起" : "详情"}</Button>}
      </div>
    </div>
    {expanded && row.preview && <div className="mt-4"><PreviewDetail preview={row.preview} /></div>}
  </div>;
}

function PreviewDetail({ preview }: { preview: ManualContentPreview }) {
  return <div className="space-y-5">
    <Card className="overflow-hidden">
      <div className="bg-gradient-to-br from-accent to-[#5856d6] p-6 text-white shadow-[0_16px_48px_rgba(0,122,255,0.25)] sm:p-8">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div><div className="flex flex-wrap gap-2"><Badge className="bg-white/15 text-white">{TYPE_META[preview.contentType].label}</Badge>{preview.content.summary.cefrLevel && <Badge className="bg-white/15 text-white">CEFR {preview.content.summary.cefrLevel}</Badge>}{preview.existingWordId && <Badge className="bg-warning/20 text-warning">词库中已存在</Badge>}</div><h2 className="mt-4 text-3xl font-bold">{preview.term}</h2>{preview.content.summary.translation && <p className="mt-2 text-xl">{preview.content.summary.translation}</p>}{preview.content.summary.shortDefinition && <p className="mt-2 max-w-2xl text-sm leading-6 text-white/80">{preview.content.summary.shortDefinition}</p>}</div>
          <div className="rounded-2xl bg-white/10 p-4 text-sm shadow-[0_8px_32px_rgba(0,0,0,0.1)] backdrop-blur-xl"><p>{preview.sourceLanguageName} → {preview.targetLanguageName}</p><p className="mt-1 text-xs text-white/70">预览有效至 {new Date(preview.expiresAt).toLocaleTimeString("zh-CN")}</p></div>
        </div>
      </div>
    </Card>

    <div className="grid gap-5 lg:grid-cols-[1.35fr_.65fr]">
      <div className="space-y-5">
        <Card><CardHeader><CardTitle>释义与例句</CardTitle></CardHeader><CardContent className="space-y-3">{preview.content.definitions.filter((item) => item.language === preview.targetLanguage).map((definition) => <div key={`${definition.senseId}-${definition.text}`} className="rounded-[16px] border border-white/50 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><div className="flex gap-2"><Badge>{definition.partOfSpeech || "释义"}</Badge>{definition.register && <Badge tone="amber">{definition.register}</Badge>}</div><p className="mt-2 leading-7">{definition.text}</p>{definition.usageNote && <p className="mt-1 text-xs text-secondary-label">{definition.usageNote}</p>}</div>)}{preview.content.examples.map((example) => <div key={example.sentence} className="rounded-[16px] border-l-4 border-accent/40 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]"><p className="italic leading-7">{example.sentence}</p>{example.translation && <p className="mt-1 text-sm text-secondary-label">{example.translation}</p>}</div>)}</CardContent></Card>

        {preview.contentType === "SENTENCE" && <Card><CardHeader><CardTitle>句子分析</CardTitle></CardHeader><CardContent className="space-y-5">{preview.content.sentenceAnalysis.grammarNotes.map((note) => <div key={note} className="rounded-[14px] border border-accent/10 bg-accent/[0.06] p-3 text-sm text-accent shadow-[0_4px_12px_rgba(0,122,255,0.04)] backdrop-blur-sm dark:text-[#0a84ff]">{note}</div>)}{preview.content.sentenceAnalysis.keyExpressions.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-tertiary-label">关键表达</p><div className="space-y-2">{preview.content.sentenceAnalysis.keyExpressions.map((item) => <div key={item.expression} className="rounded-[14px] border border-white/50 bg-white/40 p-3 shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><b>{item.expression}</b><p className="mt-1 text-sm text-secondary-label">{item.meaning}</p>{item.note && <p className="mt-1 text-xs text-tertiary-label">{item.note}</p>}</div>)}</div></div>}{preview.content.sentenceAnalysis.variations.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-tertiary-label">替换句型</p>{preview.content.sentenceAnalysis.variations.map((item) => <div key={item.sentence} className="mb-2 rounded-[14px] bg-white/40 p-3 shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]"><p>{item.sentence}</p>{item.translation && <p className="mt-1 text-xs text-secondary-label">{item.translation}</p>}</div>)}</div>}</CardContent></Card>}

        {(preview.content.synonyms.length > 0 || preview.content.wordFamily.length > 0 || preview.content.phrases.length > 0) && <Card><CardHeader><CardTitle>关联内容</CardTitle></CardHeader><CardContent className="space-y-4"><PreviewGroup label="近义词" values={preview.content.synonyms.map((item) => `${item.word}${item.translation ? ` · ${item.translation}` : ""}`)} /><PreviewGroup label="同根词" values={preview.content.wordFamily.map((item) => `${item.word}${item.translation ? ` · ${item.translation}` : ""}`)} /><PreviewGroup label="搭配与短语" values={preview.content.phrases.map((item) => `${item.phrase}${item.translation ? ` · ${item.translation}` : ""}`)} /></CardContent></Card>}
      </div>

      <div className="space-y-5">
        <Card><CardHeader><CardTitle>学习提示</CardTitle></CardHeader><CardContent className="space-y-4">{preview.content.learning.mnemonic && <Info label="记忆提示" value={preview.content.learning.mnemonic} />}{preview.content.learning.pronunciationTip && <Info label="发音提示" value={preview.content.learning.pronunciationTip} />}{preview.content.learning.commonMistakes.map((item) => <div key={item} className="rounded-[14px] border border-warning/10 bg-warning/[0.06] p-3 text-sm text-warning-deep shadow-[0_4px_12px_rgba(255,149,0,0.04)] backdrop-blur-sm dark:text-warning">{item}</div>)}</CardContent></Card>
        <Card><CardHeader><CardTitle>模型质量</CardTitle></CardHeader><CardContent className="space-y-3">{preview.providerAttempts.map((attempt) => <div key={attempt.providerId} className="rounded-[16px] border border-white/50 bg-white/40 p-3 text-sm shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><div className="flex items-center justify-between"><b className="truncate">{attempt.providerId}</b><Badge tone={attempt.status === "SUCCESS" ? "green" : attempt.status === "FAILED" ? "red" : "amber"}>{attempt.status}</Badge></div>{attempt.metadata?.qualityScore !== undefined && <p className="mt-2 text-xs text-secondary-label">质量分 {attempt.metadata.qualityScore} · Token {attempt.metadata.inputTokens ?? "?"} + {attempt.metadata.outputTokens ?? "?"}</p>}</div>)}</CardContent></Card>
      </div>
    </div>
  </div>;
}

function PreviewGroup({ label, values }: { label: string; values: string[] }) {
  if (!values.length) return null;
  return <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-tertiary-label">{label}</p><div className="flex flex-wrap gap-2">{values.map((value) => <Badge key={value}>{value}</Badge>)}</div></div>;
}
function Info({ label, value }: { label: string; value: string }) { return <div><p className="text-xs font-medium uppercase tracking-wide text-tertiary-label">{label}</p><p className="mt-1 text-sm leading-6">{value}</p></div>; }
