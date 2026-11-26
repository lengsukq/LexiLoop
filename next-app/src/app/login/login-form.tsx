"use client";

import { FormEvent, useState } from "react";
import {
  AlertCircle,
  Database,
  Eye,
  EyeOff,
  KeyRound,
  LoaderCircle,
  LockKeyhole,
} from "lucide-react";
import { Logo } from "@/components/logo";
import { clearLocalModeClient, setLocalModeClient } from "@/lib/app-mode";

export function LoginForm({ nextPath }: { nextPath: string }) {
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [capsLock, setCapsLock] = useState(false);
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [enteringLocal, setEnteringLocal] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting || enteringLocal) return;
    setSubmitting(true);
    setError("");

    try {
      const response = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({ password }),
        cache: "no-store",
      });
      const payload = await response.json().catch(() => null) as { success?: boolean; error?: { message?: string } } | null;
      if (!response.ok || !payload?.success) {
        setError(payload?.error?.message ?? "登录失败，请重试。");
        setSubmitting(false);
        return;
      }
      clearLocalModeClient();
      window.location.assign(nextPath);
    } catch {
      setError("网络连接失败，请稍后重试。");
      setSubmitting(false);
    }
  }

  async function enterBrowserLocalMode() {
    if (submitting || enteringLocal) return;
    setEnteringLocal(true);
    setError("");
    try {
      setLocalModeClient();
      await fetch("/api/auth/local-mode", {
        method: "POST",
        headers: { "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify({ enabled: true }),
        cache: "no-store",
      }).catch(() => null);
      window.location.assign(nextPath);
    } catch {
      setError("切换本地模式失败，请稍后重试。");
      setEnteringLocal(false);
    }
  }

  return (
    <main className="relative grid min-h-screen place-items-center overflow-hidden px-5 py-10 text-label">
      <div className="pointer-events-none absolute -left-24 top-[-7rem] size-[22rem] rounded-full bg-[#0a84ff]/20 blur-3xl" />
      <div className="pointer-events-none absolute -right-24 bottom-[-7rem] size-[24rem] rounded-full bg-purple/20 blur-3xl" />

      <section className="animate-scale-in relative w-full max-w-[430px]">
        <div className="liquid-glass-elevated liquid-glass-specular liquid-glass-edge overflow-hidden rounded-[34px] p-7 shadow-[0_30px_100px_rgba(0,0,0,0.14)] sm:p-10">
          <div className="relative z-10">
            <Logo size="lg" className="mb-8" />

            <div className="mb-7">
              <div className="mb-2 flex items-center gap-2 text-accent">
                <LockKeyhole className="size-4" />
                <span className="text-[12px] font-bold uppercase tracking-[0.16em]">Private space</span>
              </div>
              <h1 className="text-[30px] font-bold leading-tight tracking-[-0.045em]">欢迎回来</h1>
              <p className="mt-2 text-[15px] leading-6 text-secondary-label">输入密码连接云端词库，或无需密码直接在浏览器本地学习。</p>
            </div>

            <form onSubmit={submit} className="space-y-4">
              <label className="block">
                <span className="mb-2 block text-[13px] font-semibold text-secondary-label">云端登录密码</span>
                <div className="glass-inner flex items-center gap-3 rounded-[17px] px-4 py-3.5 focus-within:ring-2 focus-within:ring-accent/30">
                  <KeyRound className="size-[18px] shrink-0 text-quaternary-label" />
                  <input
                    autoFocus
                    required
                    type={showPassword ? "text" : "password"}
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                    onKeyUp={(event) => setCapsLock(event.getModifierState("CapsLock"))}
                    onKeyDown={(event) => setCapsLock(event.getModifierState("CapsLock"))}
                    placeholder="输入密码"
                    autoComplete="current-password"
                    className="min-w-0 flex-1 bg-transparent text-[16px] outline-none placeholder:text-tertiary-label dark:placeholder:text-[#636366]"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword((prev) => !prev)}
                    className="ios-press grid size-7 place-items-center rounded-full text-tertiary-label hover:text-label"
                    title={showPassword ? "隐藏密码" : "显示密码"}
                  >
                    {showPassword ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
                  </button>
                </div>
              </label>

              {capsLock && (
                <p className="flex items-center gap-1.5 text-xs font-medium text-warning dark:text-warning">
                  <AlertCircle className="size-3.5" />已开启大写锁定 (Caps Lock)
                </p>
              )}

              {error && <p role="alert" className="rounded-[14px] bg-danger/10 px-3.5 py-3 text-[13px] font-medium leading-5 text-danger-deep dark:text-[#ff6961]">{error}</p>}

              <button
                type="submit"
                disabled={submitting || enteringLocal}
                className="ios-press flex w-full items-center justify-center gap-2 rounded-[17px] bg-accent px-4 py-3.5 text-[15px] font-bold text-white shadow-[0_10px_24px_rgba(0,122,255,0.27)] transition hover:bg-[#006fe6] disabled:cursor-wait disabled:opacity-70"
              >
                {submitting && <LoaderCircle className="size-4 animate-spin" />}
                {submitting ? "正在验证…" : "登录云端词库"}
              </button>
            </form>

            <div className="my-5 flex items-center gap-3 text-[12px] text-tertiary-label">
              <div className="h-px flex-1 bg-black/[0.08] dark:bg-white/[0.1]" />
              <span>或免密试用 / 离线使用</span>
              <div className="h-px flex-1 bg-black/[0.08] dark:bg-white/[0.1]" />
            </div>

            <button
              type="button"
              onClick={() => void enterBrowserLocalMode()}
              disabled={submitting || enteringLocal}
              className="ios-press glass-inner flex w-full items-center justify-center gap-2 rounded-[17px] border border-black/[0.07] px-4 py-3 text-[14px] font-semibold text-label transition hover:bg-white/70 disabled:cursor-wait disabled:opacity-70 dark:border-white/[0.1] dark:hover:bg-white/[0.08]"
            >
              {enteringLocal ? <LoaderCircle className="size-4 animate-spin" /> : <Database className="size-4 text-accent" />}
              {enteringLocal ? "正在进入本地模式…" : "无需密码 · 使用浏览器本地模式"}
            </button>
            <p className="mt-2.5 text-center text-[11.5px] leading-5 text-tertiary-label dark:text-[#7c7c80]">
              数据库直接存于当前浏览器的 IndexedDB（PostgreSQL WASM），不读写云端数据，后续也可随时导入导出或与云端同步。
            </p>
          </div>
        </div>
      </section>
    </main>
  );
}
