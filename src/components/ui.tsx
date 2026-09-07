"use client";

import { useEffect, useId, useRef, useState, type ButtonHTMLAttributes, type HTMLAttributes, type InputHTMLAttributes, type ReactNode } from "react";
import { ChevronDown, ChevronLeft, ChevronRight, Search, Loader2 } from "lucide-react";
import { motion, AnimatePresence } from "framer-motion";
import { cn } from "@/lib/cn";

export function buttonClass(
  variant: "primary" | "secondary" | "outline" | "ghost" | "danger" = "primary",
  size: "sm" | "md" | "lg" = "md",
) {
  return cn(
    "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-2xl font-medium tracking-tight transition-all duration-200 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-accent/40 disabled:pointer-events-none disabled:opacity-40 ios-press",
    size === "sm" ? "h-9 px-3.5 text-[13px]" : size === "lg" ? "h-[50px] px-7 text-[16px] font-semibold" : "h-10 px-4.5 text-[14px]",
    variant === "primary" && "bg-accent text-white shadow-[0_2px_8px_rgba(0,122,255,0.25),inset_0_1px_0_rgba(255,255,255,0.28)] hover:shadow-[0_4px_16px_rgba(0,122,255,0.35)] hover:brightness-105 active:brightness-95",
    variant === "secondary" && "bg-accent/10 text-accent hover:bg-accent/[0.14] dark:bg-accent/[0.14] dark:hover:bg-accent/20",
    variant === "outline" && "border border-black/[0.08] bg-white/70 text-label shadow-[0_1px_2px_rgba(0,0,0,0.02)] backdrop-blur-xl hover:bg-white hover:border-black/[0.12] hover:shadow-[0_4px_12px_rgba(0,0,0,0.04)] dark:border-white/[0.1] dark:bg-white/[0.06] dark:hover:bg-white/[0.1]",
    variant === "ghost" && "text-secondary-label hover:bg-black/[0.04] hover:text-label dark:hover:bg-white/[0.06] dark:hover:text-[#f5f5f7]",
    variant === "danger" && "bg-danger text-white shadow-[0_2px_8px_rgba(255,59,48,0.25),inset_0_1px_0_rgba(255,255,255,0.28)] hover:shadow-[0_4px_16px_rgba(255,59,48,0.35)] hover:brightness-105",
  );
}

export { toast, ToastContainer } from "./toast";

/**
 * 带有 Apple Spring 物理效果的平滑数字递增动画组件
 */
export function AnimatedCounter({
  value,
  duration = 0.65,
  className,
  prefix = "",
  suffix = "",
}: {
  value: number;
  duration?: number;
  className?: string;
  prefix?: string;
  suffix?: string;
}) {
  const [display, setDisplay] = useState(value);
  const prevRef = useRef(value);

  useEffect(() => {
    const start = prevRef.current;
    const end = value;
    prevRef.current = end;
    if (start === end) return;

    const startTime = performance.now();
    const durationMs = duration * 1000;

    let rafId: number;
    const update = (now: number) => {
      const elapsed = now - startTime;
      const progress = Math.min(1, elapsed / durationMs);
      // Apple-like cubic ease out
      const eased = 1 - Math.pow(1 - progress, 3);
      const current = Math.round(start + (end - start) * eased);
      setDisplay(current);

      if (progress < 1) {
        rafId = requestAnimationFrame(update);
      } else {
        setDisplay(end);
      }
    };

    rafId = requestAnimationFrame(update);
    return () => cancelAnimationFrame(rafId);
  }, [value, duration]);

  return <span className={cn("num-tabular", className)}>{prefix}{display.toLocaleString()}{suffix}</span>;
}

/**
 * 实时发音波形律动组件（用于发音播报状态展示）
 */
export function AudioWave({ active = false, className }: { active?: boolean; className?: string }) {
  return (
    <span className={cn("inline-flex items-end gap-[2px] h-3.5 w-3.5 py-0.5", className)} aria-hidden="true">
      <span className={cn("w-[2px] rounded-full bg-current transition-all", active ? "animate-wave-1" : "h-[30%]")} />
      <span className={cn("w-[2px] rounded-full bg-current transition-all", active ? "animate-wave-2" : "h-[70%]")} />
      <span className={cn("w-[2px] rounded-full bg-current transition-all", active ? "animate-wave-3" : "h-[45%]")} />
      <span className={cn("w-[2px] rounded-full bg-current transition-all", active ? "animate-wave-4" : "h-[85%]")} />
    </span>
  );
}

export function Kbd({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <kbd
      className={cn(
        "inline-flex items-center justify-center rounded-md border border-black/[0.08] bg-black/[0.03] px-1.5 py-0.5 font-mono text-[10px] font-semibold text-secondary-label dark:border-white/12 dark:bg-white/[0.06] dark:text-secondary-label",
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
        "liquid-glass-elevated liquid-glass-specular overflow-hidden rounded-[22px] transition-all duration-300 sm:rounded-[24px]",
        className,
      )}
      {...props}
    />
  );
}

export function CardHeader({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("relative z-10 px-4.5 pb-2 pt-4.5 sm:px-6 sm:pt-5.5", className)} {...props} />;
}

export function CardContent({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("relative z-10 px-4.5 pb-4.5 pt-2 sm:px-6 sm:pb-6", className)} {...props} />;
}

export function CardTitle({ className, ...props }: HTMLAttributes<HTMLHeadingElement>) {
  return <h2 className={cn("text-[17px] font-semibold tracking-tight text-label", className)} {...props} />;
}

export function Badge({ children, tone = "slate", className }: { children: ReactNode; tone?: "slate" | "green" | "amber" | "red" | "blue" | "purple" | "glass"; className?: string }) {
  const tones = {
    slate: "bg-quaternary-label/10 text-secondary-label dark:bg-secondary-label/12",
    green: "bg-success/10 text-success-deep dark:bg-success/15 dark:text-success",
    amber: "bg-warning/10 text-warning-deep dark:bg-warning/15 dark:text-warning",
    red: "bg-danger/10 text-danger-deep dark:bg-danger/15 dark:text-danger",
    blue: "bg-accent/10 text-accent-deep dark:bg-accent/15 dark:text-accent",
    purple: "bg-purple/10 text-purple-deep dark:bg-purple/15 dark:text-purple",
    glass: "border border-white/30 bg-white/[0.22] text-white shadow-[inset_0_1px_0_rgba(255,255,255,0.3)] backdrop-blur-md",
  } as const;
  return <span className={cn("inline-flex items-center rounded-full px-2.5 py-0.5 text-[11px] font-semibold tracking-tight", tones[tone], className)}>{children}</span>;
}

export function Progress({ value, max = 100, indeterminate = false, className }: { value: number; max?: number; indeterminate?: boolean; className?: string }) {
  const percent = Math.max(0, Math.min(100, max ? (value / max) * 100 : 0));
  return (
    <div className={cn("h-[6px] overflow-hidden rounded-full bg-black/[0.05] dark:bg-white/[0.08]", className)}>
      <div
        className={cn("h-full rounded-full bg-gradient-to-r from-accent to-[#5ac8fa] shadow-[0_1px_3px_rgba(0,122,255,0.25)]", indeterminate ? "animate-progress-slide w-2/5" : "transition-all duration-500 ease-out")}
        style={indeterminate ? undefined : { width: `${percent}%` }}
      />
    </div>
  );
}

const fieldClass = cn(
  "h-10.5 w-full rounded-[13px] border border-black/[0.08] bg-white/60 px-3.5 text-[14px] shadow-[0_1px_2px_rgba(0,0,0,0.02)] backdrop-blur-xl outline-none transition-all duration-200",
  "placeholder:text-tertiary-label focus:border-accent focus:bg-white focus:shadow-[0_4px_16px_rgba(0,122,255,0.08),0_0_0_3px_rgba(0,122,255,0.12)]",
  "dark:border-white/[0.09] dark:bg-white/[0.05] dark:placeholder:text-[#636366] dark:focus:bg-white/[0.08] dark:focus:shadow-[0_4px_16px_rgba(10,132,255,0.12),0_0_0_3px_rgba(10,132,255,0.15)]",
);

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={cn(fieldClass, className)} />;
}

export function SearchInput({ className, inputClassName, ...props }: InputHTMLAttributes<HTMLInputElement> & { inputClassName?: string }) {
  return (
    <div className={cn("relative", className)}>
      <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-tertiary-label" />
      <input {...props} className={cn(fieldClass, "h-9.5 pl-8.5 text-[13.5px]", inputClassName)} />
    </div>
  );
}

export function Select({ className, compact = false, ...props }: React.SelectHTMLAttributes<HTMLSelectElement> & { compact?: boolean }) {
  return (
    <div className={cn("relative", className)}>
      <select
        {...props}
        className={cn(
          "w-full appearance-none rounded-[13px] border border-black/[0.08] bg-white/60 shadow-[0_1px_2px_rgba(0,0,0,0.02)] backdrop-blur-xl outline-none transition-all focus:border-accent focus:bg-white focus:shadow-[0_4px_16px_rgba(0,122,255,0.08)] dark:border-white/[0.09] dark:bg-white/[0.05] dark:focus:bg-white/[0.08]",
          compact ? "h-8 pl-3 pr-7 text-xs font-medium" : "h-10.5 pl-3.5 pr-9 text-[14px]",
          props.disabled && "opacity-40",
        )}
      />
      <ChevronDown className={cn("pointer-events-none absolute top-1/2 -translate-y-1/2 text-tertiary-label", compact ? "right-2 size-3.5" : "right-3 size-4")} />
    </div>
  );
}

export function Segmented<T extends string>({
  options,
  value,
  onChange,
  className,
  id,
}: {
  options: Array<{ value: T; label: string }>;
  value: T;
  onChange: (value: T) => void;
  className?: string;
  id?: string;
}) {
  const autoId = useId();
  const gliderId = id ?? autoId;

  return (
    <div className={cn("relative inline-flex gap-1 rounded-[14px] bg-black/[0.04] p-1 backdrop-blur-xl dark:bg-white/[0.06]", className)} role="tablist">
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
              "relative flex-1 whitespace-nowrap rounded-[10px] px-3.5 py-1.5 text-[13px] font-medium transition-colors duration-200 focus-visible:outline-none",
              active
                ? "text-[#1c1c1e] font-semibold dark:text-white"
                : "text-secondary-label hover:text-[#1c1c1e] dark:text-secondary-label dark:hover:text-white",
            )}
          >
            {active && (
              <motion.div
                layoutId={`segmented-glider-${gliderId}`}
                className="absolute inset-0 rounded-[10px] bg-white shadow-[0_2px_8px_rgba(0,0,0,0.08),0_1px_2px_rgba(0,0,0,0.04)] dark:bg-white/[0.16] dark:shadow-[0_2px_8px_rgba(0,0,0,0.3)]"
                transition={{ type: "spring", stiffness: 500, damping: 36 }}
              />
            )}
            <span className="relative z-10">{option.label}</span>
          </button>
        );
      })}
    </div>
  );
}

export function Alert({ tone = "danger", icon, children, className }: { tone?: "danger" | "info" | "success"; icon?: ReactNode; children: ReactNode; className?: string }) {
  const tones = {
    danger: "border-danger/15 bg-danger/[0.05] text-danger-deep dark:text-danger",
    info: "border-accent/15 bg-accent/[0.05] text-accent-deep dark:text-[#64b5ff]",
    success: "border-success/15 bg-success/[0.05] text-success-deep dark:text-success",
  } as const;
  return (
    <div className={cn("flex items-start gap-2.5 rounded-[16px] border p-3.5 text-[13.5px] leading-relaxed backdrop-blur-md", tones[tone], className)}>
      {icon && <span className="mt-0.5 shrink-0">{icon}</span>}
      <div className="min-w-0">{children}</div>
    </div>
  );
}

export function EmptyState({ icon, title, description, action }: { icon?: ReactNode; title: string; description: string; action?: ReactNode }) {
  return (
    <div className="liquid-glass-elevated animate-scale-in flex min-h-56 flex-col items-center justify-center rounded-[24px] p-6 text-center sm:min-h-64 sm:rounded-[28px] sm:p-10">
      {icon}
      <h2 className="mt-4 text-lg font-semibold tracking-tight text-label sm:text-xl">{title}</h2>
      <p className="mt-1.5 max-w-md text-[14px] leading-relaxed text-secondary-label">{description}</p>
      {action && <div className="mt-5">{action}</div>}
    </div>
  );
}

export function PageHeader({ title, description, action }: { title: string; description?: string; action?: ReactNode }) {
  return (
    <div className="animate-fade-down flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h1 className="text-[26px] font-bold tracking-tight text-label sm:text-[28px]">{title}</h1>
        {description && <p className="mt-1 text-[14px] text-secondary-label leading-relaxed">{description}</p>}
      </div>
      {action}
    </div>
  );
}

export function Dialog({ open, onClose, title, children, maxWidth = "max-w-lg", keepMounted = false }: { open: boolean; onClose: () => void; title: string; children: ReactNode; maxWidth?: string; keepMounted?: boolean }) {
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
    <AnimatePresence>
      {open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.2 }}
            className="absolute inset-0 bg-black/25 backdrop-blur-sm"
            onClick={onClose}
          />
          <motion.div
            initial={{ opacity: 0, scale: 0.94, y: 10 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.95, y: 8 }}
            transition={{ type: "spring", duration: 0.32, bounce: 0.12 }}
            className={cn(
              "liquid-glass-elevated liquid-glass-specular relative z-10 max-h-[85vh] w-full overflow-y-auto rounded-[24px] p-6 shadow-[0_24px_60px_-12px_rgba(0,0,0,0.22)] sm:rounded-[26px]",
              maxWidth,
            )}
          >
            <div className="mb-4 flex items-center justify-between">
              <h2 className="text-lg font-bold tracking-tight text-label">{title}</h2>
              <button
                onClick={onClose}
                className="ios-press grid size-7 place-items-center rounded-full bg-black/[0.05] text-secondary-label hover:bg-black/[0.08] dark:bg-white/[0.08] dark:hover:bg-white/[0.12]"
                aria-label="关闭对话框"
              >
                <svg className="size-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" d="M6 18L18 6M6 6l12 12" /></svg>
              </button>
            </div>
            {children}
          </motion.div>
        </div>
      )}
    </AnimatePresence>
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
    sticky ? "grid size-8.5 place-items-center rounded-[10px] sm:size-9 sm:rounded-[11px]" : "grid size-9.5 place-items-center rounded-[11px]",
    "ios-press border border-black/[0.06] bg-white/70 shadow-[0_1px_2px_rgba(0,0,0,0.02)] backdrop-blur-md transition disabled:pointer-events-none disabled:opacity-30 dark:border-white/[0.08] dark:bg-white/[0.06]",
  );
}

export function Pagination({ page, totalPages, total, onChange, className, sticky = false }: {
  page: number; totalPages: number; total?: number; onChange: (page: number) => void; className?: string; sticky?: boolean;
}) {
  if (totalPages <= 1) return null;
  return (
    <div className={cn(
      sticky ? "flex-row items-center justify-between gap-2" : "flex-col items-center gap-3 sm:flex-row sm:justify-between",
      sticky && "liquid-glass liquid-glass-specular sticky top-3 z-20 mx-auto w-full overflow-hidden rounded-[18px] px-3 py-2 shadow-[0_8px_24px_-4px_rgba(0,0,0,0.08)] sm:rounded-[20px] sm:px-4 sm:py-2.5",
      className,
    )}>
      {total !== undefined && <p className={cn("text-xs font-medium text-secondary-label num-tabular", sticky && "whitespace-nowrap")}>共 {total} 条</p>}
      <nav className={cn("flex items-center gap-1", sticky && "gap-1")}>
        <button className={pageButtonClass(sticky)} disabled={page <= 1} onClick={() => onChange(page - 1)} aria-label="上一页">
          <ChevronLeft className="size-4" />
        </button>
        {paginationRange(page, totalPages).map((item, index) =>
          item === "..." ? (
            <span key={`ellipsis-${index}`} className="px-1 text-xs text-tertiary-label">…</span>
          ) : (
            <button
              key={item}
              className={cn(
                sticky ? "ios-press size-8.5 rounded-[10px] text-[13px] font-medium transition-all duration-150 sm:size-9 sm:rounded-[11px]" : "ios-press size-9.5 rounded-[11px] text-[13px] font-medium transition-all duration-150",
                item === page
                  ? "bg-accent text-white shadow-[0_2px_8px_rgba(0,122,255,0.3)]"
                  : "border border-black/[0.06] bg-white/70 text-secondary-label shadow-[0_1px_2px_rgba(0,0,0,0.02)] backdrop-blur-md hover:bg-white dark:border-white/[0.08] dark:bg-white/[0.06] dark:hover:bg-white/[0.1]",
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

