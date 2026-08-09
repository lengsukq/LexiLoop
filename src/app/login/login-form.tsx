"use client";

import { FormEvent, useState } from "react";
import { KeyRound, LoaderCircle, LockKeyhole } from "lucide-react";
import { Logo } from "@/components/logo";

export function LoginForm({ nextPath }: { nextPath: string }) {
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submitting) return;
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
      window.location.assign(nextPath);
    } catch {
      setError("网络连接失败，请稍后重试。");
      setSubmitting(false);
    }
  }

  return (
    <main className="relative grid min-h-screen place-items-center overflow-hidden px-5 py-10 text-[#1c1c1e] dark:text-[#f5f5f7]">
      <div className="pointer-events-none absolute -left-24 top-[-7rem] size-[22rem] rounded-full bg-[#0a84ff]/20 blur-3xl" />
      <div className="pointer-events-none absolute -right-24 bottom-[-7rem] size-[24rem] rounded-full bg-[#af52de]/20 blur-3xl" />

      <section className="animate-scale-in relative w-full max-w-[430px]">
        <div className="liquid-glass-elevated liquid-glass-specular liquid-glass-edge overflow-hidden rounded-[34px] p-7 shadow-[0_30px_100px_rgba(0,0,0,0.14)] sm:p-10">
          <div className="relative z-10">
            <Logo size="lg" className="mb-8" />

            <div className="mb-7">
              <div className="mb-2 flex items-center gap-2 text-[#007aff] dark:text-[#0a84ff]">
                <LockKeyhole className="size-4" />
                <span className="text-[12px] font-bold uppercase tracking-[0.16em]">Private space</span>
              </div>
              <h1 className="text-[30px] font-bold leading-tight tracking-[-0.045em]">欢迎回来</h1>
              <p className="mt-2 text-[15px] leading-6 text-[#6e6e73] dark:text-[#98989d]">输入密码，继续你的词汇循环。</p>
            </div>

            <form onSubmit={submit} className="space-y-4">
              <label className="block">
                <span className="mb-2 block text-[13px] font-semibold text-[#6e6e73] dark:text-[#98989d]">登录密码</span>
                <div className="glass-inner flex items-center gap-3 rounded-[17px] px-4 py-3.5 focus-within:ring-2 focus-within:ring-[#007aff]/30">
                  <KeyRound className="size-[18px] shrink-0 text-[#8e8e93]" />
                  <input
                    autoFocus
                    required
                    type="password"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                    placeholder="输入密码"
                    autoComplete="current-password"
                    className="min-w-0 flex-1 bg-transparent text-[16px] outline-none placeholder:text-[#aeaeb2] dark:placeholder:text-[#636366]"
                  />
                </div>
              </label>

              {error && <p role="alert" className="rounded-[14px] bg-[#ff3b30]/10 px-3.5 py-3 text-[13px] font-medium leading-5 text-[#d70015] dark:text-[#ff6961]">{error}</p>}

              <button
                type="submit"
                disabled={submitting}
                className="ios-press flex w-full items-center justify-center gap-2 rounded-[17px] bg-[#007aff] px-4 py-3.5 text-[15px] font-bold text-white shadow-[0_10px_24px_rgba(0,122,255,0.27)] transition hover:bg-[#006fe6] disabled:cursor-wait disabled:opacity-70"
              >
                {submitting && <LoaderCircle className="size-4 animate-spin" />}
                {submitting ? "正在验证…" : "进入 LexiLoop"}
              </button>
            </form>

            <p className="mt-7 text-center text-[12px] text-[#aeaeb2] dark:text-[#636366]">这是一个私人、自托管的学习空间</p>
          </div>
        </div>
      </section>
    </main>
  );
}
