import type { ReactNode } from "react";
import { Blocks, Brain, Hammer, Headphones, Layers, Puzzle } from "lucide-react";
import type { LeaderboardSummary } from "@/lib/types";
import type { GameItem } from "./types";

import { GAME_MODES, type GameMode } from "@/modules/games/service";

export { GAME_MODES, type GameMode };

export interface GameSession {
  sessionId: number;
  mode: GameMode;
  durationSeconds: number;
  items: GameItem[];
}

export interface GameResult {
  sessionId: number;
  mode: GameMode;
  score: number;
  firstTryCorrect: number;
  recovered: number;
  missed: number;
  total: number;
  accuracy: number;
  mistakeCount: number;
  maxCombo: number;
  elapsedMs: number;
  leaderboard?: LeaderboardSummary;
}

export interface GameConfigEntry {
  title: string;
  subtitle: string;
  rule: string;
  icon: ReactNode;
  gradient: string;
}

export const GAME_CONFIG = {
  WORD_BUILDER: {
    title: "单词拼图",
    subtitle: "根据释义组合字母",
    rule: "点击打乱的字母拼出英文词条",
    icon: <Puzzle className="size-7" />,
    gradient: "from-warning to-[#ff6961]",
  },
  LISTENING_PICK: {
    title: "听音辨词",
    subtitle: "听发音快速选词",
    rule: "听到发音后，从四个词中选出正确答案",
    icon: <Headphones className="size-7" />,
    gradient: "from-[#5ac8fa] to-accent",
  },
  MEANING_BLITZ: {
    title: "词义冲刺",
    subtitle: "限时选择正确释义",
    rule: "看到英文后，快速选择对应的中文释义",
    icon: <Brain className="size-7" />,
    gradient: "from-purple to-[#5856d6]",
  },
  WHACK_A_MOLE: {
    title: "词汇地鼠",
    subtitle: "锤出正确单词",
    rule: "看释义，在地鼠缩回前锤中正确单词",
    icon: <Hammer className="size-7" />,
    gradient: "from-success to-[#00c7be]",
  },
  WORD_STACK: {
    title: "单词堆堆乐",
    subtitle: "点词块搭高塔",
    rule: "看释义，点选滚动词块堆高塔",
    icon: <Layers className="size-7" />,
    gradient: "from-[#ff2d55] to-warning",
  },
  WORD_TETRIS: {
    title: "词汇俄罗斯方块",
    subtitle: "点词块消堆叠",
    rule: "看释义，点中下落的正确单词",
    icon: <Blocks className="size-7" />,
    gradient: "from-[#5856d6] to-purple",
  },
} satisfies Record<GameMode, GameConfigEntry>;

export function validMode(value: string | null): value is GameMode {
  return Boolean(value && GAME_MODES.includes(value as GameMode));
}

export function getGameConfig(mode: GameMode): GameConfigEntry {
  return GAME_CONFIG[mode];
}
