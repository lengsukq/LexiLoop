import { Plus } from "lucide-react";
import type { RelatedWordItem } from "@/lib/types";
import { Badge, Card, CardContent, CardHeader, CardTitle } from "@/components/ui";
import type { RelationType, WordDetail } from "../word-detail-types";

export function ExtendedContentCard({
  word,
  onRelatedSelect,
}: {
  word: WordDetail;
  onRelatedSelect: (item: RelatedWordItem, relation: RelationType) => Promise<void>;
}) {
  const content = word.content;
  const hasContent = content.forms.length
    || content.phrases.length
    || content.synonyms.length
    || content.antonyms.length
    || content.wordFamily.length
    || content.confusedWords.length
    || content.roots.length
    || content.affixes.length
    || content.tags.length;
  if (!hasContent) return null;

  return <Card>
    <CardHeader><CardTitle>扩展信息</CardTitle></CardHeader>
    <CardContent className="space-y-5">
      {content.forms.length > 0 && <Group label="词形" values={content.forms.map((item) => `${item.type}: ${item.value}`)} />}
      {content.phrases.length > 0 && <Group label="搭配与短语" values={content.phrases.map((item) => `${item.phrase}${item.translation ? ` · ${item.translation}` : ""}`)} />}
      {content.synonyms.length > 0 && <RelatedGroup label="近义词" values={content.synonyms} relation="SYNONYM" onSelect={onRelatedSelect} />}
      {content.antonyms.length > 0 && <RelatedGroup label="反义词" values={content.antonyms} relation="ANTONYM" onSelect={onRelatedSelect} />}
      {content.wordFamily.length > 0 && <RelatedGroup label="同根词 / 词族" values={content.wordFamily} relation="WORD_FAMILY" onSelect={onRelatedSelect} />}
      {content.confusedWords.length > 0 && <RelatedGroup label="易混词" values={content.confusedWords} relation="CONFUSED_WITH" onSelect={onRelatedSelect} />}
      {content.roots.length > 0 && <Group label="词根" values={content.roots.map((item) => `${item.root}: ${item.meaning}${item.origin ? ` (${item.origin})` : ""}`)} />}
      {content.affixes.length > 0 && <Group label="词缀" values={content.affixes.map((item) => `${item.type === "PREFIX" ? "前缀" : "后缀"} ${item.value}: ${item.meaning}`)} />}
      {content.tags.length > 0 && <Group label="标签" values={content.tags} />}
    </CardContent>
  </Card>;
}

function Group({ label, values }: { label: string; values: string[] }) {
  return <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p><div className="flex flex-wrap gap-2">{values.map((value) => <Badge key={value}>{value}</Badge>)}</div></div>;
}

function RelatedGroup({
  label,
  values,
  relation,
  onSelect,
}: {
  label: string;
  values: RelatedWordItem[];
  relation: RelationType;
  onSelect: (item: RelatedWordItem, relation: RelationType) => Promise<void>;
}) {
  return <div><p className="mb-2 text-xs font-medium uppercase tracking-wide text-[#aeaeb2]">{label}</p><div className="flex flex-wrap gap-2">{values.map((item) => <button key={`${relation}-${item.word}`} type="button" onClick={() => void onSelect(item, relation)} className="group inline-flex items-center gap-1.5 rounded-full border border-white/50 bg-white/50 px-3 py-1 text-xs font-medium shadow-[0_2px_8px_rgba(0,0,0,0.04)] transition hover:border-[#007aff]/30 hover:bg-[#007aff]/[0.08] hover:text-[#007aff] dark:border-white/[0.08] dark:bg-white/[0.06] dark:hover:text-[#0a84ff]"><span>{item.word}</span><Plus className="size-3 opacity-45 transition group-hover:opacity-100" /></button>)}</div></div>;
}
