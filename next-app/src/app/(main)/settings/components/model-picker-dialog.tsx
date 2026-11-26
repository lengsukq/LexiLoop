import { X } from "lucide-react";
import type { LlmProviderConfig } from "@/lib/types";
import { Button, Card, CardHeader, CardTitle, Input } from "@/components/ui";
import type { ModelPickerState } from "../settings-shared";

export function ModelPickerDialog({
  state,
  provider,
  filter,
  onFilterChange,
  onToggle,
  onSelectAll,
  onClear,
  onApply,
  onClose,
}: {
  state: ModelPickerState;
  provider: LlmProviderConfig;
  filter: string;
  onFilterChange: (value: string) => void;
  onToggle: (model: string) => void;
  onSelectAll: () => void;
  onClear: () => void;
  onApply: () => void;
  onClose: () => void;
}) {
  const existing = new Set(provider.models ?? []);
  const visible = state.models.filter((model) => model.toLocaleLowerCase().includes(filter.trim().toLocaleLowerCase()));

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <button type="button" aria-label="关闭模型选择" className="absolute inset-0 bg-[#101522]/35 backdrop-blur-sm" onClick={onClose} />
      <Card className="relative z-10 flex max-h-[min(720px,calc(100vh-2rem))] w-full max-w-2xl flex-col overflow-hidden border-white/70 shadow-[0_32px_90px_rgba(15,23,42,0.28)] dark:border-white/[0.12]">
        <CardHeader className="shrink-0 border-b border-black/[0.06] dark:border-white/[0.08]">
          <div className="flex items-start justify-between gap-4"><div><CardTitle>选择要加入的模型</CardTitle><p className="mt-1 text-sm text-secondary-label">来自 {provider.name || provider.id} 的 Models 接口；已存在的模型会保留。</p></div><Button variant="ghost" size="sm" onClick={onClose} aria-label="关闭"><X className="size-4" /></Button></div>
          <div className="mt-4 flex flex-wrap items-center gap-2"><Input className="min-w-48 flex-1" value={filter} onChange={(event) => onFilterChange(event.target.value)} placeholder="筛选模型名称…" autoFocus /><Button variant="outline" size="sm" type="button" onClick={onSelectAll}>全选新增</Button><Button variant="ghost" size="sm" type="button" onClick={onClear}>清空</Button></div>
        </CardHeader>
        <div className="min-h-0 flex-1 overflow-y-auto p-3 sm:p-4">
          {visible.length ? <div className="grid gap-2 sm:grid-cols-2">{visible.map((model) => <ModelOption key={model} model={model} exists={existing.has(model)} selected={state.selected.includes(model)} onToggle={onToggle} />)}</div> : <p className="py-12 text-center text-sm text-quaternary-label">没有匹配的模型。</p>}
        </div>
        <div className="flex shrink-0 items-center justify-between gap-3 border-t border-black/[0.06] bg-white/45 px-4 py-3 backdrop-blur-sm dark:border-white/[0.08] dark:bg-white/[0.04]"><span className="text-sm text-secondary-label">已选择 {state.selected.length} 个新增模型</span><div className="flex gap-2"><Button variant="ghost" onClick={onClose}>取消</Button><Button onClick={onApply} disabled={!state.selected.length}>加入 {state.selected.length} 个</Button></div></div>
      </Card>
    </div>
  );
}

function ModelOption({ model, exists, selected, onToggle }: { model: string; exists: boolean; selected: boolean; onToggle: (model: string) => void }) {
  const checked = exists || selected;
  return <label className={`flex min-w-0 cursor-pointer items-center gap-3 rounded-xl border px-3 py-2.5 text-sm transition ${checked ? "border-accent/30 bg-accent/[0.07]" : "border-black/[0.06] bg-white/40 hover:border-accent/20 hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.04]"} ${exists ? "cursor-default opacity-65" : ""}`}><input type="checkbox" checked={checked} disabled={exists} onChange={() => onToggle(model)} className="size-4 shrink-0 accent-accent" /><span className="min-w-0 flex-1 truncate font-medium" title={model}>{model}</span>{exists && <span className="shrink-0 text-[11px] text-quaternary-label">已存在</span>}</label>;
}
