"use client";

import { useMemo, useState } from "react";
import {
  AlertCircle,
  AudioLines,
  BookOpen,
  ChevronDown,
  ChevronRight,
  Ear,
  Flag,
  FlaskConical,
  GraduationCap,
  Layers,
  Lightbulb,
  Mic2,
  Scale,
  Search,
  Sparkles,
  Volume2,
} from "lucide-react";
import { Badge, Card, CardContent, Segmented } from "@/components/ui";
import { playCachedTts } from "@/lib/tts-client";
import {
  ACCENT_DIFFS,
  CATEGORY_META,
  CONTRAST_GROUPS,
  LEARNING_PATH,
  PHONEMES,
  getPhoneme,
  type PhonemeEntry,
} from "@/modules/phonetics/catalog";

type LearnTab = "chart" | "contrast" | "accent" | "path";
type FilterKey = "all" | "vowel" | "consonant";

const VOWEL_CATS = new Set(["vowel-front", "vowel-central", "vowel-back", "diphthong"]);
const CONS_CATS = new Set(["plosive", "fricative", "affricate", "nasal", "lateral", "approximant"]);

function groupByLabel(items: PhonemeEntry[]) {
  const map = new Map<string, PhonemeEntry[]>();
  for (const p of items) {
    if (!map.has(p.groupLabel)) map.set(p.groupLabel, []);
    map.get(p.groupLabel)!.push(p);
  }
  return [...map.entries()];
}

function PhonemeTile({ entry, onOpen }: { entry: PhonemeEntry; onOpen: (s: string) => void }) {
  const meta = CATEGORY_META[entry.category];
  const isVowel = VOWEL_CATS.has(entry.category);
  return (
    <button
      type="button"
      onClick={() => onOpen(entry.symbol)}
      className="ios-press group relative flex flex-col rounded-[16px] border border-black/[0.06] bg-white/70 p-3 text-left shadow-[0_1px_2px_rgba(0,0,0,0.03)] backdrop-blur-xl transition hover:border-accent/25 hover:bg-white hover:shadow-[0_8px_24px_rgba(0,122,255,0.08)] dark:border-white/[0.08] dark:bg-white/[0.06] dark:hover:bg-white/[0.10]"
    >
      <span className={`inline-flex w-fit rounded-full px-2 py-0.5 text-[10px] font-bold tracking-wide text-white ${meta.color}`}>{meta.label}</span>
      <span className="mt-2 font-serif text-[22px] font-bold tracking-wide text-label">/{entry.symbol}/</span>
      <span className="text-[11px] font-semibold text-secondary-label">{entry.nameZh}</span>
      <span className="mt-1 line-clamp-2 text-[11px] leading-relaxed text-tertiary-label">{entry.what}</span>
      {!isVowel && entry.voicing !== "vowel" && (
        <span className={`mt-2 inline-flex w-fit rounded-full px-1.5 py-0.5 text-[10px] font-semibold ${entry.voicing === "voiced" ? "bg-success/10 text-success-deep" : "bg-accent/10 text-accent-deep"}`}>
          {entry.voicing === "voiced" ? "浊音" : "清音"}
        </span>
      )}
      <ChevronRight className="absolute right-2 top-2 size-3.5 text-tertiary-label opacity-0 transition group-hover:opacity-100" />
    </button>
  );
}

function DetailDialog({ symbol, onClose, onSwitch }: { symbol: string | null; onClose: () => void; onSwitch: (s: string) => void }) {
  const entry = symbol ? getPhoneme(symbol) : undefined;
  const [playing, setPlaying] = useState<string | null>(null);

  const play = async (word: string) => {
    setPlaying(word);
    try {
      await playCachedTts(word, "US", "word");
    } finally {
      setPlaying(null);
    }
  };

  if (!entry) return null;
  if (!symbol) return null;

  // Render as overlay card, not Dialog, to keep learn page context
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4">
      <div className="absolute inset-0 bg-black/30 backdrop-blur-sm" onClick={onClose} />
      <div className="liquid-glass-elevated liquid-glass-specular relative z-10 flex max-h-[88vh] w-full max-w-2xl flex-col overflow-hidden rounded-t-[26px] shadow-[0_24px_60px_rgba(0,0,0,0.18)] sm:rounded-[24px]">
        <div className="overflow-y-auto px-5 py-5 sm:px-7 sm:py-6">
          <div className="flex items-start justify-between gap-3">
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <span className={`rounded-full px-2.5 py-0.5 text-xs font-bold text-white ${CATEGORY_META[entry.category].color}`}>{entry.groupLabel}</span>
                {entry.voicing !== "vowel" && <Badge tone={entry.voicing === "voiced" ? "green" : "blue"}>{entry.voicing === "voiced" ? "浊辅音" : "清辅音"}</Badge>}
              </div>
              <h2 className="mt-3 font-serif text-4xl font-bold tracking-wide text-label">/{entry.symbol}/</h2>
              <p className="text-sm font-semibold text-secondary-label">{entry.nameZh}</p>
              <p className="mt-2 max-w-xl text-[13.5px] leading-relaxed text-secondary-label">{entry.what}</p>
            </div>
            <button onClick={onClose} className="ios-press grid size-8 place-items-center rounded-full bg-black/[0.06] text-secondary-label dark:bg-white/[0.08]">✕</button>
          </div>

          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <div className="rounded-[14px] bg-accent/[0.06] p-3.5">
              <p className="flex items-center gap-1.5 text-xs font-bold text-accent"><Mic2 className="size-3.5" /> 发音要领</p>
              <p className="mt-1.5 text-[13px] leading-relaxed text-secondary-label">{entry.articulation}</p>
              <p className="mt-2 flex items-center gap-1.5 text-xs font-semibold text-secondary-label"><Ear className="size-3.5" /> 口型</p>
              <p className="text-[13px] leading-relaxed text-quaternary-label">{entry.mouthShape}</p>
            </div>
            <div className="rounded-[14px] bg-[#34c759]/[0.06] p-3.5">
              <p className="flex items-center gap-1.5 text-xs font-bold text-success-deep"><Lightbulb className="size-3.5" /> 小技巧</p>
              <ul className="mt-1.5 list-disc space-y-1 pl-4 text-[13px] leading-relaxed text-secondary-label">
                {entry.tips.map((t) => <li key={t}>{t}</li>)}
              </ul>
            </div>
          </div>

          <div className="mt-4 rounded-[14px] border border-black/[0.06] bg-white/60 p-3.5 dark:border-white/[0.08] dark:bg-white/[0.04]">
            <p className="flex items-center gap-1.5 text-xs font-bold text-label"><BookOpen className="size-3.5" /> 常见拼写规律</p>
            <div className="mt-2 flex flex-wrap gap-1.5">
              {entry.spellings.map((s) => (
                <span key={s.pattern} className="inline-flex items-center gap-1 rounded-full border border-black/[0.06] bg-white px-2.5 py-1 text-xs dark:border-white/[0.08] dark:bg-white/[0.06]">
                  <b className="font-mono text-accent">{s.pattern}</b>
                  <span className="text-secondary-label">{s.example}</span>
                </span>
              ))}
            </div>
            {entry.accentNote && <p className="mt-2 text-xs text-tertiary-label">美英差异：{entry.accentNote}</p>}
          </div>

          <div className="mt-4">
            <p className="flex items-center gap-1.5 text-xs font-bold text-label"><Volume2 className="size-3.5" /> 例词试听（点喇叭跟读）</p>
            <div className="mt-2 grid gap-2 sm:grid-cols-3">
              {entry.examples.map((ex) => (
                <button
                  key={ex.word}
                  type="button"
                  onClick={() => void play(ex.word)}
                  className="ios-press flex items-center justify-between gap-2 rounded-[14px] border border-black/[0.06] bg-white/70 px-3 py-2.5 text-left hover:border-accent/30 dark:border-white/[0.08] dark:bg-white/[0.04]"
                >
                  <div className="min-w-0">
                    <b className="block text-[14px] leading-none">{ex.word}</b>
                    <span className="font-serif text-xs text-accent">{ex.phonetic}</span>
                    <span className="ml-1 text-xs text-tertiary-label">{ex.meaning}</span>
                  </div>
                  <span className={`grid size-7 place-items-center rounded-full ${playing === ex.word ? "bg-accent text-white" : "bg-accent/10 text-accent"}`}>
                    <Volume2 className="size-3.5" />
                  </span>
                </button>
              ))}
            </div>
          </div>

          <div className="mt-4 rounded-[14px] bg-warning/[0.07] p-3.5">
            <p className="flex items-center gap-1.5 text-xs font-bold text-warning-deep"><AlertCircle className="size-3.5" /> 中国学习者坑位</p>
            <p className="mt-1 text-[13px] leading-relaxed text-secondary-label">{entry.pitfalls}</p>
          </div>

          {entry.confusable.length > 0 && (
            <div className="mt-4">
              <p className="text-xs font-bold text-label">易混对比</p>
              <div className="mt-2 flex flex-wrap gap-1.5">
                {entry.confusable.map((sym) => {
                  const peer = getPhoneme(sym);
                  if (!peer) return null;
                  return (
                    <button
                      key={sym}
                      type="button"
                      onClick={() => onSwitch(sym)}
                      className="ios-press rounded-full border border-accent/20 bg-accent/10 px-3 py-1.5 text-xs font-semibold text-accent hover:bg-accent/15"
                    >
                      /{entry.symbol}/ ↔ /{sym}/ · {peer.nameZh}
                    </button>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

export function PhoneticLearn() {
  const [learnTab, setLearnTab] = useState<LearnTab>("chart");
  const [filter, setFilter] = useState<FilterKey>("all");
  const [query, setQuery] = useState("");
  const [detail, setDetail] = useState<string | null>(null);
  const [openContrast, setOpenContrast] = useState<string | null>(null);
  const [playingPair, setPlayingPair] = useState<string | null>(null);

  const filtered = useMemo(() => {
    let items = PHONEMES;
    if (filter === "vowel") items = items.filter((p) => VOWEL_CATS.has(p.category));
    if (filter === "consonant") items = items.filter((p) => CONS_CATS.has(p.category));
    if (query.trim()) {
      const q = query.trim().toLowerCase();
      items = items.filter(
        (p) => p.symbol.toLowerCase().includes(q) || p.nameZh.includes(q) || p.groupLabel.includes(q) || p.examples.some((e) => e.word.toLowerCase().includes(q)),
      );
    }
    return items;
  }, [filter, query]);

  const grouped = useMemo(() => groupByLabel(filtered), [filtered]);

  const playPair = async (word: string) => {
    setPlayingPair(word);
    try {
      await playCachedTts(word, "US", "word");
    } finally {
      setPlayingPair(null);
    }
  };

  return (
    <div className="mx-auto max-w-5xl space-y-5 pb-6">
      {/* Hero + path */}
      <Card className="overflow-hidden rounded-[24px]">
        <div className="relative overflow-hidden bg-gradient-to-br from-[#5856d6] via-accent to-[#00c7be] px-5 py-6 text-white sm:px-7 sm:py-7">
          <div className="absolute -right-10 -top-10 size-48 rounded-full bg-white/10 blur-2xl" />
          <div className="relative flex flex-wrap items-start justify-between gap-4">
            <div className="max-w-2xl">
              <span className="inline-flex items-center gap-1.5 rounded-full bg-white/15 px-3 py-1 text-xs font-semibold backdrop-blur"><GraduationCap className="size-3.5" /> 音标学习专区 · 从零到能拼</span>
              <h1 className="mt-3 text-2xl font-bold tracking-tight sm:text-[26px]">48 音标，7 步学透 — 讲人话、标坑位、能跟读</h1>
              <p className="mt-2 text-sm leading-relaxed text-white/80">按 BBC 音素表分步法 + 中国学习者易错点重排：先懂分类，再练口型，用最小对立验真会，最后回到单词里用。每个音都有发音要领、拼写规律和试听例词。</p>
              <div className="mt-3 flex flex-wrap gap-1.5 text-xs">
                <span className="rounded-full bg-white/15 px-2.5 py-1">一符一音，不猜拼写</span>
                <span className="rounded-full bg-white/15 px-2.5 py-1">美式/英式对照</span>
                <span className="rounded-full bg-white/15 px-2.5 py-1">最小对立验真会</span>
              </div>
            </div>
            <div className="hidden sm:grid size-20 place-items-center rounded-[18px] bg-white/15 backdrop-blur"><AudioLines className="size-9" /></div>
          </div>
        </div>
        <CardContent className="py-4 sm:py-5">
          <Segmented
            value={learnTab}
            onChange={setLearnTab}
            options={[
              { value: "chart", label: "音素表" },
              { value: "contrast", label: "易混对比" },
              { value: "accent", label: "美英差异" },
              { value: "path", label: "学习路径" },
            ]}
          />
        </CardContent>
      </Card>

      {learnTab === "path" && (
        <Card className="overflow-hidden">
          <CardContent className="py-5 sm:px-7">
            <h2 className="flex items-center gap-2 text-[15px] font-bold"><Flag className="size-4 text-accent" /> 7 步学习路径（建议按序走一遍）</h2>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              {LEARNING_PATH.map((step) => (
                <div key={step.step} className="rounded-[16px] border border-black/[0.06] bg-white/60 p-4 dark:border-white/[0.08] dark:bg-white/[0.04]">
                  <div className="flex items-center gap-2">
                    <span className="grid size-7 place-items-center rounded-full bg-accent text-xs font-bold text-white">{step.step}</span>
                    <b className="text-[14px]">{step.title}</b>
                    <span className="text-xs text-tertiary-label">{step.subtitle}</span>
                  </div>
                  <ul className="mt-2 list-disc space-y-1 pl-6 text-[13px] leading-relaxed text-secondary-label">
                    {step.points.map((p) => <li key={p}>{p}</li>)}
                  </ul>
                </div>
              ))}
            </div>
            <div className="mt-4 rounded-[14px] bg-accent/[0.06] p-3.5 text-[13px] leading-relaxed text-secondary-label">
              <b className="text-accent">怎么用好本专区：</b> 第一次按路径 1→4 逐个点开音素卡，边看口型边用例词跟读；5→6 做对比听辨；7 回单词本或进训练营做 75 秒挑战，错词会自动回流复习。
            </div>
          </CardContent>
        </Card>
      )}

      {learnTab === "chart" && (
        <>
          <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
            <div className="flex items-center gap-2">
              <Segmented value={filter} onChange={setFilter} options={[{ value: "all", label: "全部 48" }, { value: "vowel", label: "元音 20" }, { value: "consonant", label: "辅音 28" }]} />
              <span className="text-xs text-tertiary-label">{filtered.length} 个</span>
            </div>
            <div className="relative w-full sm:w-72">
              <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-tertiary-label" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="搜符号 / 名称 / 例词，如 th、ship、奥"
                className="h-9 w-full rounded-[12px] border border-black/[0.08] bg-white/70 pl-9 pr-3 text-[13px] outline-none placeholder:text-tertiary-label focus:border-accent focus:bg-white dark:border-white/[0.09] dark:bg-white/[0.05]"
              />
            </div>
          </div>

          {grouped.map(([label, items]) => (
            <div key={label}>
              <h3 className="mb-2 flex items-center gap-2 text-xs font-bold tracking-wide text-secondary-label">
                <Layers className="size-3.5" /> {label} <span className="font-normal text-tertiary-label">{items.length} 个</span>
              </h3>
              <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-4">
                {items.map((entry) => <PhonemeTile key={entry.symbol} entry={entry} onOpen={setDetail} />)}
              </div>
            </div>
          ))}
          {filtered.length === 0 && <p className="py-12 text-center text-sm text-tertiary-label">没有匹配的音素，换个关键词试试。</p>}

          <Card>
            <CardContent className="py-4 sm:px-6">
              <h3 className="flex items-center gap-2 text-[13px] font-bold"><FlaskConical className="size-4 text-accent" /> 记忆小窍门（来自母语者教法）</h3>
              <ul className="mt-2 grid gap-2 text-[13px] leading-relaxed text-secondary-label sm:grid-cols-2">
                <li>• <b>纸巾测试</b>清辅音送气：/p t k/ 会吹动纸巾，/b d ɡ/ 不会。</li>
                <li>• <b>喉咙震动</b>辨清浊：手摸喉咙，浊音震、清音不震。</li>
                <li>• <b>照镜子</b>看口型：圆唇/咧嘴/张口度是否到位，比耳朵更可靠。</li>
                <li>• <b>时长即词义</b>：长短元音靠拉长区分，刻意做作就对了。</li>
              </ul>
            </CardContent>
          </Card>
        </>
      )}

      {learnTab === "contrast" && (
        <div className="space-y-3">
          <div className="rounded-[14px] bg-accent/[0.06] p-3.5 text-[13px] leading-relaxed text-secondary-label">
            <b className="text-accent">最小对立（Minimal Pair）</b>是一音之差的词对，能验你是否真分清。建议：先盲听两词，再跟读，最后遮住音标自检。
          </div>
          {CONTRAST_GROUPS.map((group) => {
            const open = openContrast === group.id;
            return (
              <Card key={group.id} className="overflow-hidden">
                <button type="button" onClick={() => setOpenContrast(open ? null : group.id)} className="flex w-full items-center justify-between px-4 py-3.5 text-left sm:px-6">
                  <div>
                    <p className="flex items-center gap-2 text-[14px] font-bold"><Scale className="size-4 text-accent" /> {group.title} <span className="text-xs font-normal text-tertiary-label">{group.titleEn}</span></p>
                    <p className="mt-1 max-w-2xl text-xs leading-relaxed text-quaternary-label">{group.description}</p>
                    <div className="mt-2 flex flex-wrap gap-1">
                      {group.symbols.map((s) => <span key={s} className="rounded-full bg-black/[0.06] px-2 py-0.5 font-serif text-xs dark:bg-white/[0.08]">/{s}/</span>)}
                    </div>
                  </div>
                  <span className={`ml-3 grid size-7 place-items-center rounded-full bg-black/[0.04] transition ${open ? "rotate-180" : ""} dark:bg-white/[0.08]`}><ChevronDown className="size-4" /></span>
                </button>
                {open && (
                  <div className="border-t border-black/[0.06] bg-white/40 px-4 py-4 dark:border-white/[0.06] dark:bg-white/[0.02] sm:px-6">
                    <div className="grid gap-2">
                      {group.minimalPairs.map((pair) => (
                        <div key={pair.left + pair.right} className="flex flex-col gap-2 rounded-[14px] border border-black/[0.06] bg-white px-3 py-3 dark:border-white/[0.08] dark:bg-white/[0.04] sm:flex-row sm:items-center sm:justify-between">
                          <div className="flex flex-1 items-center gap-3">
                            <button type="button" onClick={() => void playPair(pair.left)} className={`ios-press inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold ${playingPair === pair.left ? "bg-accent text-white" : "bg-accent/10 text-accent"}`}>
                              <Volume2 className="size-3.5" /> {pair.left} <span className="font-serif font-normal">{pair.leftPh}</span>
                            </button>
                            <span className="text-tertiary-label">—</span>
                            <button type="button" onClick={() => void playPair(pair.right)} className={`ios-press inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-semibold ${playingPair === pair.right ? "bg-accent text-white" : "bg-black/[0.06] text-secondary-label dark:bg-white/[0.08]"}`}>
                              <Volume2 className="size-3.5" /> {pair.right} <span className="font-serif font-normal">{pair.rightPh}</span>
                            </button>
                          </div>
                          <span className="text-xs text-tertiary-label">{pair.meaningLeft} / {pair.meaningRight}</span>
                        </div>
                      ))}
                    </div>
                    <p className="mt-3 flex items-center gap-1.5 text-xs font-semibold text-success-deep"><Sparkles className="size-3.5" /> 关键：{group.keyTip}</p>
                  </div>
                )}
              </Card>
            );
          })}
        </div>
      )}

      {learnTab === "accent" && (
        <div className="space-y-3">
          <Card>
            <CardContent className="py-4 sm:px-6">
              <h3 className="flex items-center gap-2 text-[13px] font-bold"><Flag className="size-4 text-accent" /> 美式（GA）vs 英式（RP）快速对照</h3>
              <p className="mt-1 text-xs leading-relaxed text-quaternary-label">本区其余内容默认同时标注，学哪种口音就盯哪一列。美音标志是卷舌 r 与 /ɒ→ɑ/ 合并、闪音。</p>
              <div className="mt-3 overflow-hidden rounded-[14px] border border-black/[0.06] dark:border-white/[0.08]">
                <div className="grid grid-cols-[1fr_auto_auto_1fr] gap-px bg-black/[0.06] text-xs dark:bg-white/[0.06]">
                  <div className="bg-white p-2.5 font-semibold dark:bg-black">变化</div>
                  <div className="bg-white p-2.5 text-center font-semibold dark:bg-black">英式</div>
                  <div className="bg-white p-2.5 text-center font-semibold dark:bg-black">美式</div>
                  <div className="bg-white p-2.5 font-semibold dark:bg-black">例词</div>
                  {ACCENT_DIFFS.map((row) => (
                    <>
                      <div key={`${row.symbol}-a`} className="bg-white p-2.5 dark:bg-black"><span className="font-mono font-bold text-accent">{row.symbol}</span><span className="ml-1 text-tertiary-label">{row.note}</span></div>
                      <div className="bg-white p-2.5 text-center font-serif dark:bg-black">{row.uk}</div>
                      <div className="bg-white p-2.5 text-center font-serif dark:bg-black">{row.us}</div>
                      <div className="bg-white p-2.5 dark:bg-black"><b>{row.word}</b> <span className="text-tertiary-label">{row.example}</span></div>
                    </>
                  ))}
                </div>
              </div>
              <div className="mt-3 rounded-[12px] bg-warning/[0.07] p-3 text-xs leading-relaxed text-secondary-label">
                <b className="text-warning-deep">选口音建议：</b> 国内考试（四六级/考研）偏英式，托福/日常交流偏美式。先定一种为主，另一种当对照听懂即可，不必两套都精。
              </div>
            </CardContent>
          </Card>
          <Card>
            <CardContent className="py-4 sm:px-6">
              <h3 className="text-[13px] font-bold">拼写 ≠ 发音（别被拼写骗了）</h3>
              <ul className="mt-2 list-disc space-y-1 pl-5 text-[13px] leading-relaxed text-secondary-label">
                <li><b>ough</b> 有 6 读：though /ðəʊ/、through /θruː/、thought /θɔːt/、enough /ɪˈnʌf/、cough /kɒf/、borough /ˈbʌrə/</li>
                <li><b>a</b> 有四读：cat /æ/、name /eɪ/、father /ɑː/、about /ə/</li>
                <li><b>ea</b> 有三读：sea /iː/、head /e/、great /eɪ/</li>
                <li>规律是统计倾向，不是铁律；不确定就查音标，别猜。</li>
              </ul>
            </CardContent>
          </Card>
        </div>
      )}

      {detail && <DetailDialog symbol={detail} onClose={() => setDetail(null)} onSwitch={setDetail} />}
    </div>
  );
}
