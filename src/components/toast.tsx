"use client";

import { useEffect, useState } from "react";
import { AlertCircle, CheckCircle2, Info, X } from "lucide-react";
import { cn } from "@/lib/cn";

export type ToastType = "success" | "error" | "info";

export interface ToastMessage {
  id: string;
  type: ToastType;
  title?: string;
  message: string;
  duration?: number;
}

const TOAST_EVENT = "lexiloop:toast";

export const toast = {
  success(message: string, title?: string, duration = 3000) {
    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent(TOAST_EVENT, {
          detail: { id: Math.random().toString(36).slice(2), type: "success", message, title, duration },
        }),
      );
    }
  },
  error(message: string, title?: string, duration = 4500) {
    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent(TOAST_EVENT, {
          detail: { id: Math.random().toString(36).slice(2), type: "error", message, title, duration },
        }),
      );
    }
  },
  info(message: string, title?: string, duration = 3000) {
    if (typeof window !== "undefined") {
      window.dispatchEvent(
        new CustomEvent(TOAST_EVENT, {
          detail: { id: Math.random().toString(36).slice(2), type: "info", message, title, duration },
        }),
      );
    }
  },
};

export function ToastContainer() {
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  useEffect(() => {
    function handleToast(event: Event) {
      const customEvent = event as CustomEvent<ToastMessage>;
      const newToast = customEvent.detail;
      setToasts((prev) => [...prev.slice(-3), newToast]);

      const duration = newToast.duration ?? 3000;
      window.setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== newToast.id));
      }, duration);
    }

    window.addEventListener(TOAST_EVENT, handleToast);
    return () => window.removeEventListener(TOAST_EVENT, handleToast);
  }, []);

  if (toasts.length === 0) return null;

  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 top-3 z-50 flex flex-col items-center gap-2 px-4 sm:top-5"
    >
      {toasts.map((item) => (
        <div
          key={item.id}
          className={cn(
            "pointer-events-auto flex w-full max-w-sm items-center gap-3 rounded-[20px] p-3.5 shadow-[0_16px_48px_rgba(0,0,0,0.18),0_4px_16px_rgba(0,0,0,0.08)] backdrop-blur-2xl transition-all animate-fade-down duration-300 sm:max-w-md sm:px-4 sm:py-3",
            "liquid-glass liquid-glass-specular border border-white/60 dark:border-white/15 dark:bg-[#1c1c1e]/90",
            item.type === "success" && "border-success/30 text-success-deep dark:text-success",
            item.type === "error" && "border-danger/30 text-danger-deep dark:text-danger",
            item.type === "info" && "border-accent/30 text-accent-deep dark:text-[#64b5ff]",
          )}
        >
          <div className="shrink-0">
            {item.type === "success" && <CheckCircle2 className="size-5 text-success" />}
            {item.type === "error" && <AlertCircle className="size-5 text-danger" />}
            {item.type === "info" && <Info className="size-5 text-accent" />}
          </div>
          <div className="min-w-0 flex-1">
            {item.title && <p className="text-[13px] font-bold text-label">{item.title}</p>}
            <p className="text-[14px] font-medium leading-snug text-label">{item.message}</p>
          </div>
          <button
            type="button"
            onClick={() => setToasts((prev) => prev.filter((t) => t.id !== item.id))}
            className="ios-press -mr-1 grid size-7 shrink-0 place-items-center rounded-full text-tertiary-label hover:bg-black/[0.06] hover:text-label dark:hover:bg-white/[0.08]"
            aria-label="关闭提示"
          >
            <X className="size-3.5" />
          </button>
        </div>
      ))}
    </div>
  );
}
