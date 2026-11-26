"use client";
import { useEffect } from "react";
import { apiFetch } from "@/lib/client-api";

/** 全局后台 tick 完成事件：detail 为保活接口返回结果，页面可监听以刷新数据。 */
export const BACKGROUND_TICK_EVENT = "lexiloop:background-tick";

export interface KeepaliveResult {
  running: boolean;
  queued: number;
  claimed: number;
  elapsedMs: number;
}

// 有待处理任务时高频推进；空闲时低频探活（维持维护任务与每日建议推进）；失败退避避免死循环快速重试。
const ACTIVE_INTERVAL_MS = 3_000;
const IDLE_INTERVAL_MS = 60_000;
const RETRY_BACKOFF_MS = 10_000;

/**
 * 全局常驻保活组件：挂载在 AppShell 内，跨页面切换不卸载。
 * 周期性调用 /api/background/keepalive 触发服务端 tick，使初始化队列在任意页面都能持续推进；
 * 完成后派发 BACKGROUND_TICK_EVENT 供页面订阅刷新。
 */
export function BackgroundKeepalive() {
  useEffect(() => {
    let cancelled = false;
    let timer: number | undefined;
    let inFlight = false;

    function schedule(delayMs: number) {
      if (cancelled) return;
      window.clearTimeout(timer);
      timer = window.setTimeout(() => void tick(), delayMs);
    }

    async function tick() {
      if (cancelled || inFlight || document.hidden) return;
      inFlight = true;
      try {
        const result = await apiFetch<KeepaliveResult>("/api/background/keepalive");
        if (cancelled) return;
        window.dispatchEvent(new CustomEvent(BACKGROUND_TICK_EVENT, { detail: result }));
        schedule(result.running || result.queued > 0 ? ACTIVE_INTERVAL_MS : IDLE_INTERVAL_MS);
      } catch (error) {
        console.warn("[BackgroundKeepalive] 保活请求失败", error);
        if (!cancelled) schedule(RETRY_BACKOFF_MS);
      } finally {
        inFlight = false;
      }
    }

    function onVisibilityChange() {
      if (document.hidden) {
        window.clearTimeout(timer);
      } else {
        void tick(); // 回到前台立即保活一次
      }
    }

    void tick(); // 挂载后立即保活一次
    document.addEventListener("visibilitychange", onVisibilityChange);
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      document.removeEventListener("visibilitychange", onVisibilityChange);
    };
  }, []);

  return null;
}
