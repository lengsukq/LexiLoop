"use client";

import { useEffect, useState } from "react";
import { AlertCircle, CheckCircle2, Info, X } from "lucide-react";
import { cn } from "@/lib/cn";

import { motion, AnimatePresence } from "framer-motion";

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

  return (
    <div
      aria-live="polite"
      className="pointer-events-none fixed inset-x-0 top-3 z-50 flex flex-col items-center gap-2 px-4 sm:top-4.5"
    >
      <AnimatePresence mode="popLayout">
        {toasts.map((item) => (
          <motion.div
            key={item.id}
            layout
            initial={{ opacity: 0, y: -16, scale: 0.94 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, scale: 0.92, y: -10 }}
            transition={{ type: "spring", stiffness: 500, damping: 35 }}
            className={cn(
              "pointer-events-auto flex w-full max-w-sm items-center gap-2.5 rounded-[16px] p-3 shadow-[0_12px_36px_-4px_rgba(0,0,0,0.14),0_2px_8px_rgba(0,0,0,0.04)] backdrop-blur-2xl sm:max-w-md sm:px-3.5 sm:py-2.5",
              "liquid-glass border border-black/[0.08] dark:border-white/15 dark:bg-[#1c1c1e]/90",
              item.type === "success" && "border-success/25",
              item.type === "error" && "border-danger/25",
              item.type === "info" && "border-accent/25",
            )}
          >
            <div className="shrink-0">
              {item.type === "success" && <CheckCircle2 className="size-4.5 text-success" />}
              {item.type === "error" && <AlertCircle className="size-4.5 text-danger" />}
              {item.type === "info" && <Info className="size-4.5 text-accent" />}
            </div>
            <div className="min-w-0 flex-1">
              {item.title && <p className="text-xs font-semibold text-label">{item.title}</p>}
              <p className="text-[13px] font-medium leading-snug text-label">{item.message}</p>
            </div>
            <button
              type="button"
              onClick={() => setToasts((prev) => prev.filter((t) => t.id !== item.id))}
              className="ios-press -mr-0.5 grid size-6 shrink-0 place-items-center rounded-full text-tertiary-label hover:bg-black/[0.05] hover:text-label dark:hover:bg-white/[0.08]"
              aria-label="关闭提示"
            >
              <X className="size-3.5" />
            </button>
          </motion.div>
        ))}
      </AnimatePresence>
    </div>
  );
}
