"use client";

import Link from "next/link";
import { useState } from "react";
import { AlertCircle, ArrowRight, BookPlus, CheckCircle2, Loader2, RefreshCw, Sparkles } from "lucide-react";
import { apiFetch } from "@/lib/client-api";
import type { EntryType, ManualContentPreview } from "@/lib/types";
import { Badge, Button, Card, CardContent, CardHeader, CardTitle, PageHeader, Select, buttonClass } from "@/components/ui";

type TypeChoice = "AUTO" | EntryType;

const TYPE_META: Record<EntryType, { label: string; description: string }> = {
  WORD: { label: "单词", description: "生成词性、词形、词根、同根词和搭配" },
  PHRASE: { label: "短语", description: "生成不同含义、固定搭配和自然例句" },
  SENTENCE: { label: "句子", description: "生成翻译、语法分析、关键表达和替换句型" },
};

export default function CreatePage() {
  const [text, setText] = useState("");
  const [typeChoice, setTypeChoice] = useState<TypeChoice>("AUTO");
  const [sourceLanguage, setSourceLanguage] = useState("en");
  const [targetLanguage, setTargetLanguage] = useState("zh-CN");
  const [preview, setPreview] = useState<ManualContentPreview | null>(null);
  const [busy, setBusy] = useState<"preview" | "confirm" | "">("");
  const [error, setError] = useState("");
  const [confirmed, setConfirmed] = useState<{ wordId: number; created: boolean; contentType: EntryType } | null>(null);

  async function generatePreview() {
    setBusy("preview");
    setError("");
    setConfirmed(null);
    try {
      const data = await apiFetch<ManualContentPreview>("/api/manual/preview", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text,
          sourceLanguage,
          targetLanguage,
          ...(typeChoice === "AUTO" ? {} : { contentType: typeChoice }),
        }),
      });
      setPreview(data);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "生成预览失败");
    } finally {
      setBusy("");
    }
  }

  async function confirm() {
    if (!preview) return;
    setBusy("confirm");
    setError("");
    try {
      const result = await apiFetch<{ wordId: number; created: boolean; contentType: EntryType }>("/api/manual/confirm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ previewToken: preview.previewToken }),
      });
      setConfirmed(result);
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : "确认添加失败");
    } finally {
      setBusy("");
    }
  }

  function reset() {
    setPreview(null);
    setConfirmed(null);
    setError("");
  }

  return <div className="space-y-6">
    <PageHeader title="手动添加" description="输入单词、短语或句子，先由 AI 生成完整预览，确认后才正式进入词库。" />

    <Card>
      <CardHeader><CardTitle className="flex items-center gap-2"><BookPlus className="size-5 text-[#007aff]" />输入学习内容</CardTitle></CardHeader>
      <CardContent className="space-y-5">
        <textarea
          className="glass-inner min-h-36 w-full rounded-[18px] p-4 text-lg outline-none transition placeholder:text-[#aeaeb2] focus:border-[#007aff]/40 focus:shadow-[0_8px_32px_rgba(0,122,255,0.10),0_0_0_4px_rgba(0,122,255,0.08)]"
          value={text}
          onChange={(event) => { setText(event.target.value); if (preview) reset(); }}
          placeholder={'例如：\nabandon\nbreak down\nI have been working here for five years.'}
          maxLength={1200}
        />
        <div className="grid gap-4 md:grid-cols-3">
          <label className="space-y-2"><span className="text-sm font-medium">内容类型</span><Select className="w-full" value={typeChoice} onChange={(event) => setTypeChoice(event.target.value as TypeChoice)}><option value="AUTO">自动判断</option><option value="WORD">单词</option><option value="PHRASE">短语</option><option value="SENTENCE">句子</option></Select></label>
          <label className="space-y-2"><span className="text-sm font-medium">原语言</span><Select className="w-full" value={sourceLanguage} onChange={(event) => setSourceLanguage(event.target.value)}><option value="en">英语</option><option value="zh-CN">简体中文</option><option value="ja">日语</option><option value="ko">韩语</option><option value="fr">法语</option><option value="de">德语</option><option value="es">西班牙语</option></Select></label>
          <label className="space-y-2"><span className="text-sm font-medium">目标语言</span><Select className="w-full" value={targetLanguage} onChange={(event) => setTargetLanguage(event.target.value)}><option value="zh-CN">简体中文</option><option value="en">英语</option><option value="ja">日语</option><option value="ko">韩语</option><option value="fr">法语</option><option value="de">德语</option><option value="es">西班牙语</option></Select></label>
        </div>
        <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-xs text-[#aeaeb2]">生成预览会调用一次已配置的大模型，但不会创建正式词条。</p>
          <Button size="lg" onClick={() => void generatePreview()} disabled={!text.trim() || busy !== ""}>{busy === "preview" ? <Loader2 className="size-5 animate-spin" /> : <Sparkles className="size-5" />}{preview ? "重新生成预览" : "生成 AI 预览"}</Button>
        </div>
      </CardContent>
    </Card>

    {error && <div className="flex items-start gap-2 rounded-[18px] border border-[#ff3b30]/15 bg-[#ff3b30]/[0.06] p-4 text-sm text-[#d70015] shadow-[0_8px_32px_rgba(255,59,48,0.06)] backdrop-blur-xl dark:text-[#ff453a]"><AlertCircle className="mt-0.5 size-4 shrink-0" />{error}</div>}

    {preview && <div className="space-y-5">
      <Card className="overflow-hidden">
        <div className="bg-gradient-to-br from-[#007aff] to-[#5856d6] p-6 text-white shadow-[0_16px_48px_rgba(0,122,255,0.25)] sm:p-8">
          <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
            <div><div className="flex flex-wrap gap-2"><Badge className="bg-white/15 text-white">{TYPE_META[preview.contentType].label}</Badge>{preview.content.summary.cefrLevel && <Badge className="bg-white/15 text-white">CEFR {preview.content.summary.cefrLevel}</Badge>}{preview.existingWordId && <Badge className="bg-[#ff9500]/20 text-[#ff9500]">词库中已存在</Badge>}</div><h2 className="mt-4 text-3xl font-bold">{preview.term}</h2>{preview.content.summary.translation && <p className="mt-2 text-xl">{preview.content.summary.translation}</p>}{preview.content.summary.shortDefinition && <p className="mt-2 max-w-2xl text-sm leading-6 text-white/80">{preview.content.summary.shortDefinition}</p>}</div>
            <div className="rounded-2xl bg-white/10 p-4 text-sm shadow-[0_8px_32px_rgba(0,0,0,0.1)] backdrop-blur-xl"><p>{preview.sourceLanguageName} → {preview.targetLanguageName}</p><p className="mt-1 text-xs text-white/70">预览有效至 {new Date(preview.expiresAt).toLocaleTimeString("zh-CN")}</p></div>
          </div>
        </div>
      </Card>

      <div className="grid gap-5 lg:grid-cols-[1.35fr_.65fr]">
        <div className="space-y-5">
          <Card><CardHeader><CardTitle>释义与例句</CardTitle></CardHeader><CardContent className="space-y-3">{preview.content.definitions.filter((item) => item.language === preview.targetLanguage).map((definition) => <div key={`${definition.senseId}-${definition.text}`} className="rounded-[16px] border border-white/50 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><div className="flex gap-2"><Badge>{definition.partOfSpeech || "释义"}</Badge>{definition.register && <Badge tone="amber">{definition.register}</Badge>}</div><p className="mt-2 leading-7">{definition.text}</p>{definition.usageNote && <p className="mt-1 text-xs text-[#6e6e73] dark:text-[#98989d]">{definition.usageNote}</p>}</div>)}{preview.content.examples.map((example) => <div key={example.sentence} className="rounded-[16px] border-l-4 border-[#007aff]/40 bg-white/40 p-4 shadow-[0_4px_16px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]"><p className="italic leading-7">{example.sentence}</p>{example.translation && <p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d]">{example.translation}</p>}</div>)}</CardContent></Card>

          {preview.contentType === "SENTENCE" && <Card><CardHeader><CardTitle>句子分析</CardTitle></CardHeader><CardContent className="space-y-5">{preview.content.sentenceAnalysis.grammarNotes.map((note) => <div key={note} className="rounded-[14px] border border-[#007aff]/10 bg-[#007aff]/[0.06] p-3 text-sm text-[#007aff] shadow-[0_4px_12px_rgba(0,122,255,0.04)] backdrop-blur-sm dark:text-[#0a84ff]">{note}</div>)}{preview.content.sentenceAnalysis.keyExpressions.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">关键表达</p><div className="space-y-2">{preview.content.sentenceAnalysis.keyExpressions.map((item) => <div key={item.expression} className="rounded-[14px] border border-white/50 bg-white/40 p-3 shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><b>{item.expression}</b><p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d]">{item.meaning}</p>{item.note && <p className="mt-1 text-xs text-[#aeaeb2]">{item.note}</p>}</div>)}</div></div>}{preview.content.sentenceAnalysis.variations.length > 0 && <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">替换句型</p>{preview.content.sentenceAnalysis.variations.map((item) => <div key={item.sentence} className="mb-2 rounded-[14px] bg-white/40 p-3 shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:bg-white/[0.04]"><p>{item.sentence}</p>{item.translation && <p className="mt-1 text-xs text-[#6e6e73] dark:text-[#98989d]">{item.translation}</p>}</div>)}</div>}</CardContent></Card>}

          {(preview.content.synonyms.length > 0 || preview.content.wordFamily.length > 0 || preview.content.phrases.length > 0) && <Card><CardHeader><CardTitle>关联内容</CardTitle></CardHeader><CardContent className="space-y-4"><PreviewGroup label="近义词" values={preview.content.synonyms.map((item) => `${item.word}${item.translation ? ` · ${item.translation}` : ""}`)} /><PreviewGroup label="同根词" values={preview.content.wordFamily.map((item) => `${item.word}${item.translation ? ` · ${item.translation}` : ""}`)} /><PreviewGroup label="搭配与短语" values={preview.content.phrases.map((item) => `${item.phrase}${item.translation ? ` · ${item.translation}` : ""}`)} /></CardContent></Card>}
        </div>

        <div className="space-y-5">
          <Card><CardHeader><CardTitle>学习提示</CardTitle></CardHeader><CardContent className="space-y-4">{preview.content.learning.mnemonic && <Info label="记忆提示" value={preview.content.learning.mnemonic} />}{preview.content.learning.pronunciationTip && <Info label="发音提示" value={preview.content.learning.pronunciationTip} />}{preview.content.learning.commonMistakes.map((item) => <div key={item} className="rounded-[14px] border border-[#ff9500]/10 bg-[#ff9500]/[0.06] p-3 text-sm text-[#c93400] shadow-[0_4px_12px_rgba(255,149,0,0.04)] backdrop-blur-sm dark:text-[#ff9f0a]">{item}</div>)}</CardContent></Card>
          <Card><CardHeader><CardTitle>模型质量</CardTitle></CardHeader><CardContent className="space-y-3">{preview.providerAttempts.map((attempt) => <div key={attempt.providerId} className="rounded-[16px] border border-white/50 bg-white/40 p-3 text-sm shadow-[0_4px_12px_rgba(0,0,0,0.03)] backdrop-blur-sm dark:border-white/[0.06] dark:bg-white/[0.04]"><div className="flex items-center justify-between"><b className="truncate">{attempt.providerId}</b><Badge tone={attempt.status === "SUCCESS" ? "green" : attempt.status === "FAILED" ? "red" : "amber"}>{attempt.status}</Badge></div>{attempt.metadata?.qualityScore !== undefined && <p className="mt-2 text-xs text-[#6e6e73] dark:text-[#98989d]">质量分 {attempt.metadata.qualityScore} · Token {attempt.metadata.inputTokens ?? "?"} + {attempt.metadata.outputTokens ?? "?"}</p>}</div>)}</CardContent></Card>
        </div>
      </div>

      {confirmed ? <Card><CardContent className="py-10 text-center"><CheckCircle2 className="mx-auto size-12 text-[#34c759]" /><h2 className="mt-3 text-xl font-bold">{confirmed.created ? "已加入词库" : "已有词条已更新"}</h2><p className="mt-2 text-sm text-[#6e6e73] dark:text-[#98989d]">AI 预览内容已经正式保存，可以立即开始学习。</p><div className="mt-5 flex justify-center gap-3"><Link href={`/words/${confirmed.wordId}`} className={buttonClass("primary")}><ArrowRight className="size-4" />打开词条</Link><Button variant="outline" onClick={() => { setText(""); reset(); }}>继续添加</Button></div></CardContent></Card> : <Card><CardContent className="flex flex-col gap-4 pt-5 sm:flex-row sm:items-center sm:justify-between"><div><p className="font-semibold">确认后才会写入正式词库</p><p className="mt-1 text-sm text-[#6e6e73] dark:text-[#98989d]">确认不会再次调用模型。后续可在词条详情点击近义词、同根词等继续加入。</p></div><div className="flex gap-2"><Button variant="outline" onClick={() => void generatePreview()} disabled={busy !== ""}>{busy === "preview" ? <Loader2 className="size-4 animate-spin" /> : <RefreshCw className="size-4" />}重新生成</Button><Button size="lg" onClick={() => void confirm()} disabled={busy !== ""}>{busy === "confirm" ? <Loader2 className="size-5 animate-spin" /> : <CheckCircle2 className="size-5" />}确认加入词库</Button></div></CardContent></Card>}
    </div>}
  </div>;
}

function PreviewGroup({ label, values }: { label: string; values: string[] }) {
  if (!values.length) return null;
  return <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p><div className="flex flex-wrap gap-2">{values.map((value) => <Badge key={value}>{value}</Badge>)}</div></div>;
}
function Info({ label, value }: { label: string; value: string }) { return <div><p className="text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p><p className="mt-1 text-sm leading-6">{value}</p></div>; }
