import Link from "next/link";
import { ArrowLeft, AudioLines, Gamepad2, Loader2, Zap } from "lucide-react";
import { Badge, Card, CardContent, buttonClass } from "@/components/ui";
import { GameErrorBanner } from "@/components/game-hud";
import { GAME_CONFIG, GAME_MODES, type GameMode } from "./games-config";

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
    <div className="mx-auto max-w-4xl space-y-5 py-2 sm:py-6">
      <div className="flex items-center justify-between">
        <Link href="/" className={buttonClass("ghost", "sm")}><ArrowLeft className="size-4" />返回</Link>
        <Badge tone="purple"><Gamepad2 className="size-3.5" />趣味训练</Badge>
      </div>
      <Card className="overflow-hidden">
        <div className="relative overflow-hidden bg-gradient-to-br from-[#5856d6] via-accent to-[#5ac8fa] px-5 py-8 text-center text-white sm:px-10 sm:py-11">
          <div className="absolute -right-16 -top-16 size-48 rounded-full bg-white/10 blur-3xl" />
          <span className="relative mx-auto grid size-16 place-items-center rounded-[20px] bg-white/15 backdrop-blur-xl"><Zap className="size-8" /></span>
          <h1 className="relative mt-5 text-2xl font-bold tracking-tight sm:text-3xl">趣味英语训练</h1>
          <p className="relative mx-auto mt-2 max-w-xl text-sm leading-relaxed text-white/75 sm:text-[15px]">独立于每日复习队列。错词、近期忘记和模糊的词会优先出现在小游戏中。</p>
        </div>
        <CardContent className="space-y-5 py-5 sm:px-8 sm:py-7">
          <div className="grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            {ENTRY_LINKS.map((entry) => (
              <Link key={entry.href} href={entry.href} className={`ios-press glass-inner group flex items-center gap-4 rounded-[18px] border border-white/40 p-4 transition-all dark:border-white/[0.08] ${entry.hoverClass}`}>
                <span className={`grid size-12 shrink-0 place-items-center rounded-[15px] bg-gradient-to-br ${entry.iconGradient} text-white shadow-lg`}>{entry.icon}</span>
                <span className="min-w-0"><b className="block text-[16px]">{entry.title}</b><small className="mt-1 block text-[13px] text-quaternary-label">{entry.subtitle}</small></span>
              </Link>
            ))}
            {GAME_MODES.map((gameMode) => {
              const config = GAME_CONFIG[gameMode];
              return (
                <button key={gameMode} type="button" onClick={() => onStart(gameMode)} disabled={loading} className="ios-press glass-inner group flex items-center gap-4 rounded-[18px] border border-white/40 p-4 text-left transition-all hover:border-accent/35 hover:shadow-[0_10px_32px_rgba(0,122,255,0.12)] disabled:opacity-50 dark:border-white/[0.08]">
                  <span className={`grid size-12 shrink-0 place-items-center rounded-[15px] bg-gradient-to-br ${config.gradient} text-white shadow-lg`}>
                    {loading && loadingMode === gameMode ? <Loader2 className="size-6 animate-spin" /> : config.icon}
                  </span>
                  <span className="min-w-0"><b className="block text-[16px]">{config.title}</b><small className="mt-1 block text-[13px] text-quaternary-label">{config.subtitle}</small></span>
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
