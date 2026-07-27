import { Badge } from "@/components/ui";
export function InitializationBadge({ status }: { status: string }) {
  const map: Record<string, { label: string; tone: "slate" | "green" | "amber" | "red" | "blue" }> = {
    PENDING: { label: "待初始化", tone: "slate" }, QUEUED: { label: "排队中", tone: "blue" }, RUNNING: { label: "初始化中", tone: "blue" },
    READY: { label: "已就绪", tone: "green" }, PARTIAL: { label: "部分完成", tone: "amber" }, FAILED: { label: "失败", tone: "red" }, DISABLED: { label: "已禁用", tone: "slate" },
  };
  const value = map[status] ?? { label: status, tone: "slate" as const };
  return <Badge tone={value.tone}>{value.label}</Badge>;
}
export function MasteryBadge({ level }: { level: string }) {
  const map: Record<string, { label: string; tone: "slate" | "blue" | "green" | "purple" }> = {
    NEW: { label: "新词", tone: "slate" }, LEARNING: { label: "学习中", tone: "blue" }, FAMILIAR: { label: "熟悉", tone: "green" }, PROFICIENT: { label: "熟练", tone: "purple" }, MASTERED: { label: "已掌握", tone: "purple" },
  };
  const value = map[level] ?? { label: level, tone: "slate" as const };
  return <Badge tone={value.tone}>{value.label}</Badge>;
}
