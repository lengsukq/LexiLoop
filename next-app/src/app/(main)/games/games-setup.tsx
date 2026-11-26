import Link from "next/link";
import { ArrowLeft, AudioLines, Gamepad2, Loader2, Zap } from "lucide-react";
import { Badge, Card, CardContent, buttonClass } from "@/components/ui";
import { GameErrorBanner } from "@/components/game-hud";
import { getGameConfig, GAME_MODES, type GameMode } from "./games-config";

const ENTRY_LINKS = [
  {
    href: "/match",
    title: "限时词汇配对",
    subtitle: "英文与释义组队配对 · 连击计分",
    icon: <Gamepad2 className="size-6" />,
    iconGradient: "from-purple to-[#5856d6]",
    hoverClass: "hover:border-purple/35 hover:shadow-[0_10px_32px_rgba(175,82,222,0.12)]",
  },
  {
    href: "/phonetics",
    title: "音标辨音训练",
    subtitle: "听音、音标与单词三向匹配",
    icon: <AudioLines className="size-6" />,
    iconGradient: "from-[#00c7be] to-accent",
    hoverClass: "hover:border-[#00c7be]/35 hover:shadow-[0_10px_32px_rgba(0,199,190,0.12)]",
  },
];

export function GamesSetup({ loading, loadingMode, error, onStart }: {
  loading: boolean;
  loadingMode: GameMode | null;
  error: string;
  onStart: (mode: GameMode) => void;
}) {
  return (
    <div className="mx-auto max-w-4xl space-y-4 py-2 sm:space-y-5 sm:py-5">
      <div className="flex items-center justify-between">
        <Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回</Link>
        <Badge tone="purple"><Gamepad2 className="size-3.5" />趣味训练</Badge>
      </div>
      <Card className="overflow-hidden rounded-[24px]">
        <div className="relative overflow-hidden bg-gradient-to-br from-[#5856d6] via-accent to-[#5ac8fa] px-5 py-7 text-center text-white shadow-[inset_0_1.5px_0_rgba(255,255,255,0.3)] sm:px-8 sm:py-9">
          <div className="absolute -right-16 -top-16 size-48 rounded-full bg-white/10 blur-2xl pointer-events-none" />
          <span className="relative mx-auto grid size-13 place-items-center rounded-[16px] bg-white/20 shadow-xs backdrop-blur-md"><Zap className="size-6.5" /></span>
          <h1 className="relative mt-3.5 text-xl font-bold tracking-tight sm:text-2xl">趣味英语训练</h1>
          <p className="relative mx-auto mt-1.5 max-w-lg text-xs leading-relaxed text-white/80 sm:text-[13.5px]">独立于每日复习队列。错词、近期忘记和模糊的词会优先出现在小游戏中。</p>
        </div>
        <CardContent className="space-y-4 py-4 sm:px-7 sm:py-6">
          <div className="grid gap-2.5 md:grid-cols-2 lg:grid-cols-3">
            {ENTRY_LINKS.map((entry) => (
              <Link key={entry.href} href={entry.href} className={`ios-press group flex items-center gap-3.5 rounded-[16px] border border-black/[0.08] bg-white/60 p-3.5 transition-all hover:bg-white hover:border-black/[0.12] dark:border-white/[0.09] dark:bg-white/[0.04] ${entry.hoverClass}`}>
                <span className={`grid size-11 shrink-0 place-items-center rounded-[13px] bg-gradient-to-br ${entry.iconGradient} text-white shadow-xs`}>{entry.icon}</span>
                <span className="min-w-0"><b className="block text-[14.5px] font-semibold">{entry.title}</b><small className="mt-0.5 block text-xs text-quaternary-label">{entry.subtitle}</small></span>
              </Link>
            ))}
            {GAME_MODES.map((gameMode) => {
              const config = getGameConfig(gameMode);
              return (
                <button key={gameMode} type="button" onClick={() => onStart(gameMode)} disabled={loading} className="ios-press group flex items-center gap-3.5 rounded-[16px] border border-black/[0.08] bg-white/60 p-3.5 text-left transition-all hover:bg-white hover:border-accent/40 disabled:opacity-50 dark:border-white/[0.09] dark:bg-white/[0.04]">
                  <span className={`grid size-11 shrink-0 place-items-center rounded-[13px] bg-gradient-to-br ${config.gradient} text-white shadow-xs`}>
                    {loading && loadingMode === gameMode ? <Loader2 className="size-5 animate-spin" /> : config.icon}
                  </span>
                  <span className="min-w-0"><b className="block text-[14.5px] font-semibold">{config.title}</b><small className="mt-0.5 block text-xs text-quaternary-label">{config.subtitle}</small></span>
                </button>
              );
            })}
          </div>
          <GameErrorBanner error={error} />
        </CardContent>
      </Card>
    </div>
  );
}
