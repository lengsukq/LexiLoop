import Link from "next/link";
import { BookOpen } from "lucide-react";
import { cn } from "@/lib/cn";

const sizes = {
  md: {
    box: "size-12 rounded-[16px]",
    icon: "size-5",
    shadow: "shadow-[0_6px_20px_rgba(0,122,255,0.4),inset_0_1px_0_rgba(255,255,255,0.3)]",
    title: "text-[18px] tracking-tight",
    subtitle: "text-[11px] text-quaternary-label dark:text-[#636366]",
  },
  lg: {
    box: "size-14 rounded-[19px]",
    icon: "size-6",
    shadow: "shadow-[0_10px_30px_rgba(0,122,255,0.34),inset_0_1px_0_rgba(255,255,255,0.35)]",
    title: "text-[21px] tracking-[-0.03em]",
    subtitle: "text-[12px] text-quaternary-label dark:text-secondary-label",
  },
} as const;

/**
 * LexiLoop 品牌 logo：渐变蓝紫圆角块 + book-open 图标 + 文字标。
 * - 默认 md：顶部导航品牌区（可传 href 包裹链接）
 * - lg：登录页等大尺寸场景
 */
export function Logo({
  size = "md",
  href,
  className,
}: {
  size?: keyof typeof sizes;
  href?: string;
  className?: string;
}) {
  const s = sizes[size];
  const mark = (
    <span className={cn("grid place-items-center bg-gradient-to-br from-[#0a84ff] to-[#5856d6] text-white", s.box, s.shadow)}>
      <BookOpen className={s.icon} strokeWidth={size === "lg" ? 2.2 : 2} />
    </span>
  );
  const wordmark = (
    <div>
      <div className={cn("font-bold", s.title)}>LexiLoop</div>
      <div className={cn("font-medium", s.subtitle)}>词环 · 循环记忆</div>
    </div>
  );

  if (href) {
    return (
      <Link href={href} className={cn("ios-press relative z-10 flex items-center gap-3.5 rounded-[18px] px-3 py-3", className)}>
        {mark}
        {wordmark}
      </Link>
    );
  }
  return (
    <div className={cn("flex items-center gap-3", className)}>
      {mark}
      {wordmark}
    </div>
  );
}
