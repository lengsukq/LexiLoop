import { useEffect, type ButtonHTMLAttributes, type HTMLAttributes, type InputHTMLAttributes, type ReactNode } from "react";
import { ChevronDown, ChevronLeft, ChevronRight, Search } from "lucide-react";
import { cn } from "@/lib/cn";

export function buttonClass(
  variant: "primary" | "secondary" | "outline" | "ghost" | "danger" = "primary",
  size: "sm" | "md" | "lg" = "md",
) {
  return cn(
    "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-2xl font-semibold transition-all duration-300 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/50 disabled:pointer-events-none disabled:opacity-40 ios-press",
    size === "sm" ? "h-9 px-3.5 text-[13px]" : size === "lg" ? "h-[54px] px-8 text-[17px]" : "h-11 px-5 text-[15px]",
    variant === "primary" && "bg-gradient-to-b from-[#0a84ff] to-[#007aff] text-white shadow-[0_4px_16px_rgba(0,122,255,0.35),inset_0_1px_0_rgba(255,255,255,0.2)] hover:shadow-[0_6px_24px_rgba(0,122,255,0.4)]",
    variant === "secondary" && "bg-accent/10 text-accent shadow-[inset_0_1px_0_rgba(255,255,255,0.5)] hover:bg-accent/15 dark:bg-accent/15",
    variant === "outline" && "border border-white/50 bg-white/50 text-label shadow-[0_4px_16px_rgba(0,0,0,0.05),inset_0_1px_0_rgba(255,255,255,0.8)] backdrop-blur-2xl hover:bg-white/70 hover:shadow-[0_8px_32px_rgba(0,0,0,0.08)] dark:border-white/[0.1] dark:bg-white/[0.06]",
    variant === "ghost" && "text-secondary-label hover:bg-black/[0.04] dark:hover:bg-white/[0.08]",
    variant === "danger" && "bg-gradient-to-b from-[#ff453a] to-[#ff3b30] text-white shadow-[0_4px_16px_rgba(255,59,48,0.35),inset_0_1px_0_rgba(255,255,255,0.2)] hover:shadow-[0_6px_24px_rgba(255,59,48,0.4)]",
  );
}

import { Loader2 } from "lucide-react";
export { toast, ToastContainer } from "./toast";

export function Kbd({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <kbd
      className={cn(
        "inline-flex items-center justify-center rounded-md border border-black/10 bg-black/[0.04] px-1.5 py-0.5 font-mono text-[11px] font-semibold text-secondary-label shadow-[inset_0_-1px_0_rgba(0,0,0,0.1)] dark:border-white/15 dark:bg-white/[0.08] dark:text-secondary-label dark:shadow-[inset_0_-1px_0_rgba(255,255,255,0.1)]",
        className,
      )}
    >
      {children}
    </kbd>
  );
}

export function Button({
  className,
  variant = "primary",
  size = "md",
  loading = false,
  children,
  disabled,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: Parameters<typeof buttonClass>[0];
  size?: Parameters<typeof buttonClass>[1];
  loading?: boolean;
}) {
  return (
    <button className={cn(buttonClass(variant, size), className)} disabled={disabled || loading} {...props}>
      {loading && <Loader2 className="size-4 animate-spin shrink-0" />}
      {children}
    </button>
  );
}

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        "liquid-glass-elevated liquid-glass-specular overflow-hidden rounded-[20px] transition-all duration-300 sm:rounded-[22px]",
        className,
      )}
      {...props}
    />
  );
}

export function CardHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("relative z-10 px-4 pb-2 pt-4 sm:px-5 sm:pt-5", className)} {...props} />;
}

export function CardContent({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("relative z-10 px-4 pb-4 pt-2 sm:px-5 sm:pb-5", className)} {...props} />;
}

export function CardTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn("text-[17px] font-bold tracking-tight text-label", className)} {...props} />;
}

export function Badge({ children, tone = "slate", className }: { children: ReactNode; tone?: "slate" | "green" | "amber" | "red" | "blue" | "purple" | "glass"; className?: string }) {
  const tones = {
    slate: "bg-quaternary-label/12 text-secondary-label dark:bg-secondary-label/15",
    green: "bg-success/12 text-success-deep dark:bg-success/15",
    amber: "bg-warning/12 text-warning-deep dark:bg-warning/15",
    red: "bg-danger/12 text-danger-deep dark:bg-danger/15",
    blue: "bg-accent/12 text-accent-deep dark:bg-accent/15",
    purple: "bg-purple/12 text-purple-deep dark:bg-purple/15",
    glass: "border border-white/25 bg-white/[0.18] text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.2)] backdrop-blur-md",
  } as const;
  return <span className={cn("inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold", tones[tone], className)}>{children}</span>;
}

export function Progress({ value, max = 100, indeterminate = false, className }: { value: number; max?: number; indeterminate?: boolean; className?: string }) {
  const percent = Math.max(0, Math.min(100, max ? (value / max) * 100 : 0));
  return (
    <div className={cn("h-[7px] overflow-hidden rounded-full bg-black/[0.06] shadow-[inset_0_1px_2px_rgba(0,0,0,0.06)] dark:bg-white/[0.08]", className)}>
      <div
        className={cn("h-full rounded-full bg-gradient-to-r from-accent via-[#5ac8fa] to-accent shadow-[0_1px_4px_rgba(0,122,255,0.3)]", indeterminate ? "animate-progress-slide w-2/5" : "transition-all duration-700 ease-out")}
        style={indeterminate ? undefined : { width: `${percent}%` }}
      />
    </div>
  );
}

const fieldClass = cn(
  "h-11 w-full rounded-[14px] border border-white/50 bg-white/50 px-4 text-[15px] shadow-[0_4px_16px_rgba(0,0,0,0.04),inset_0_1px_3px_rgba(0,0,0,0.03)] backdrop-blur-2xl outline-none transition-all duration-300",
  "placeholder:text-tertiary-label focus:border-accent/40 focus:shadow-[0_8px_32px_rgba(0,122,255,0.10),0_0_0_4px_rgba(0,122,255,0.08)]",
  "dark:border-white/[0.08] dark:bg-white/[0.06] dark:placeholder:text-[#636366] dark:focus:shadow-[0_8px_32px_rgba(10,132,255,0.12),0_0_0_4px_rgba(10,132,255,0.1)]",
);

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={cn(fieldClass, className)} />;
}

export function SearchInput({ className, inputClassName, ...props }: InputHTMLAttributes<HTMLInputElement> & { inputClassName?: string }) {
  return (
    <div className={cn("relative", className)}>
      <Search className="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-tertiary-label" />
      <input {...props} className={cn(fieldClass, "h-9 pl-9 text-sm", inputClassName)} />
    </div>
  );
}

export function Select({ className, compact = false, ...props }: React.SelectHTMLAttributes<HTMLSelectElement> & { compact?: boolean }) {
  return (
    <div className={cn("relative", className)}>
      <select
        {...props}
        className={cn(
          "w-full appearance-none rounded-xl border border-white/50 bg-white/50 shadow-[0_4px_16px_rgba(0,0,0,0.04)] backdrop-blur-2xl outline-none transition-all focus:border-accent/40 focus:shadow-[0_8px_32px_rgba(0,122,255,0.10)] dark:border-white/[0.08] dark:bg-white/[0.06]",
          compact ? "h-8 pl-3 pr-8 text-xs" : "h-11 pl-4 pr-9 text-[15px]",
          props.disabled && "opacity-40",
        )}
      />
      <ChevronDown className={cn("pointer-events-none absolute top-1/2 -translate-y-1/2 text-tertiary-label", compact ? "right-2.5 size-3.5" : "right-3 size-4")} />
    </div>
  );
}

export function Segmented<T extends string>({ options, value, onChange, className }: {
  options: Array<{ value: T; label: string }>;
  value: T;
  onChange: (value: T) => void;
  className?: string;
}) {
  return (
    <div className={cn("inline-flex gap-0.5 rounded-2xl bg-white/50 p-1 shadow-[0_2px_8px_rgba(0,0,0,0.04),inset_0_1px_0_rgba(255,255,255,0.7)] backdrop-blur-2xl dark:bg-white/[0.06]", className)} role="tablist">
      {options.map((option) => {
        const active = option.value === value;
        return (
          <button
            key={option.value}
            type="button"
            role="tab"
            aria-selected={active}
            onClick={() => onChange(option.value)}
            className={cn(
              "flex-1 whitespace-nowrap rounded-xl px-3.5 py-2 text-sm font-semibold transition-all duration-200",
              active
                ? "bg-white text-[#1c1c1e] shadow-[0_2px_8px_rgba(0,0,0,0.08),inset_0_1px_0_rgba(255,255,255,0.9)] dark:bg-white/[0.14] dark:text-white"
                : "text-secondary-label hover:text-[#1c1c1e] dark:text-secondary-label dark:hover:text-white",
            )}
          >
            {option.label}
          </button>
        );
      })}
    </div>
  );
}

export function Alert({ tone = "danger", icon, children, className }: { tone?: "danger" | "info" | "success"; icon?: ReactNode; children: ReactNode; className?: string }) {
  const tones = {
    danger: "border-danger/15 bg-danger/[0.06] text-danger-deep shadow-[0_4px_16px_rgba(255,59,48,0.05)]",
    info: "border-accent/15 bg-accent/[0.06] text-accent-deep dark:text-[#64b5ff]",
    success: "border-success/15 bg-success/[0.06] text-success-deep",
  } as const;
  return (
    <div className={cn("flex items-start gap-2 rounded-[16px] border p-3 text-sm backdrop-blur-sm", tones[tone], className)}>
      {icon && <span className="mt-0.5 shrink-0">{icon}</span>}
      <div className="min-w-0">{children}</div>
    </div>
  );
}

export function EmptyState({ icon, title, description, action }: { icon?: ReactNode; title: string; description: string; action?: ReactNode }) {
  return (
    <div className="liquid-glass-elevated animate-scale-in flex min-h-56 flex-col items-center justify-center rounded-[22px] p-6 text-center sm:min-h-64 sm:rounded-[28px] sm:p-10">
      {icon}
      <h2 className="mt-4 text-xl font-bold tracking-tight text-label">{title}</h2>
      <p className="mt-2 max-w-md text-[15px] leading-relaxed text-secondary-label">{description}</p>
      {action && <div className="mt-6">{action}</div>}
    </div>
  );
}

export function PageHeader({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return (
    <div className="animate-fade-down flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="text-[28px] font-bold tracking-tight text-label">{title}</h1>
        {description && <p className="mt-1 text-[15px] text-secondary-label">{description}</p>}
      </div>
      {action}
    </div>
  );
}

export function Dialog({ open, onClose, title, children, maxWidth = "max-w-lg", keepMounted = false }: { open: boolean; onClose: () => void; title: string; children: ReactNode; maxWidth?: string; keepMounted?: boolean }) {
  // Esc 关闭 + 打开期间锁定背景滚动，与移动端弹层行为保持一致
  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => { if (event.key === "Escape") onClose(); };
    document.addEventListener("keydown", onKeyDown);
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = previousOverflow;
    };
  }, [open, onClose]);
  if (!open && !keepMounted) return null;
  return (
    <div className={`fixed inset-0 z-50 flex items-center justify-center p-4 ${open ? "" : "hidden"}`}>
      <div className="absolute inset-0 bg-black/25 backdrop-blur-md" onClick={onClose} />
      <div className={`liquid-glass-elevated liquid-glass-specular animate-scale-in relative z-10 max-h-[85vh] w-full ${maxWidth} overflow-y-auto rounded-[28px] p-6`}>
        <div className="mb-5 flex items-center justify-between">
          <h2 className="text-xl font-bold text-label">{title}</h2>
          <button onClick={onClose} className="ios-press grid size-8 place-items-center rounded-full bg-black/[0.06] text-secondary-label dark:bg-white/[0.08]">
            <svg className="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        {children}
      </div>
    </div>
  );
}

function paginationRange(page: number, totalPages: number): (number | "...")[] {
  if (totalPages <= 7) return Array.from({ length: totalPages }, (_, i) => i + 1);
  const pages: (number | "...")[] = [1];
  const start = Math.max(2, page - 1);
  const end = Math.min(totalPages - 1, page + 1);
  if (start > 2) pages.push("...");
  for (let i = start; i <= end; i++) pages.push(i);
  if (end < totalPages - 1) pages.push("...");
  pages.push(totalPages);
  return pages;
}

function pageButtonClass(sticky: boolean) {
  return cn(
    sticky ? "grid size-9 place-items-center rounded-[11px] sm:size-10 sm:rounded-[12px]" : "grid size-10 place-items-center rounded-[12px]",
    "ios-press border border-white/50 bg-white/50 shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-sm transition disabled:pointer-events-none disabled:opacity-35 dark:border-white/[0.08] dark:bg-white/[0.05]",
  );
}

export function Pagination({ page, totalPages, total, onChange, className, sticky = false }: {
  page: number; totalPages: number; total?: number; onChange: (page: number) => void; className?: string; sticky?: boolean;
}) {
  if (totalPages <= 1) return null;
  return (
    <div className={cn(
      sticky ? "flex-row items-center justify-between gap-2" : "flex-col items-center gap-3 sm:flex-row sm:justify-between",
      sticky && "liquid-glass liquid-glass-specular liquid-glass-edge sticky top-3 z-20 mx-auto w-full overflow-hidden rounded-[18px] bg-white/[0.9] px-2.5 py-2 shadow-[0_10px_28px_rgba(0,0,0,0.12),0_3px_12px_rgba(0,0,0,0.06)] backdrop-blur-2xl dark:bg-[#1c1c1e]/[0.9] sm:rounded-[20px] sm:px-4 sm:py-3",
      className,
    )}>
      {total !== undefined && <p className={cn("text-sm text-secondary-label", sticky && "whitespace-nowrap text-xs")}>共 {total} 条</p>}
      <nav className={cn("flex items-center gap-1.5", sticky && "gap-1 sm:gap-1.5")}>
        <button className={pageButtonClass(sticky)} disabled={page <= 1} onClick={() => onChange(page - 1)} aria-label="上一页">
          <ChevronLeft className="size-4" />
        </button>
        {paginationRange(page, totalPages).map((item, index) =>
          item === "..." ? (
            <span key={`ellipsis-${index}`} className="px-1 text-sm text-tertiary-label">…</span>
          ) : (
            <button
              key={item}
              className={cn(
                sticky ? "ios-press size-9 rounded-[11px] text-[13px] font-medium transition-all duration-200 sm:size-10 sm:rounded-[12px] sm:text-sm" : "ios-press size-10 rounded-[12px] text-sm font-medium transition-all duration-200",
                item === page
                  ? "bg-gradient-to-b from-[#0a84ff] to-[#007aff] text-white shadow-[0_4px_14px_rgba(0,122,255,0.35),inset_0_1px_0_rgba(255,255,255,0.2)]"
                  : "border border-white/50 bg-white/50 text-secondary-label shadow-[0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-sm hover:bg-white/70 dark:border-white/[0.08] dark:bg-white/[0.05] dark:hover:bg-white/[0.1]",
              )}
              onClick={() => onChange(item)}
            >{item}</button>
          ),
        )}
        <button className={pageButtonClass(sticky)} disabled={page >= totalPages} onClick={() => onChange(page + 1)} aria-label="下一页">
          <ChevronRight className="size-4" />
        </button>
      </nav>
    </div>
  );
}
