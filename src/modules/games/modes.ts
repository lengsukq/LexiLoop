/** 游戏模式常量独立成文件：客户端组件可直接导入，避免把 service（依赖 db/pg）打进浏览器包。 */
export const GAME_MODES = ["WORD_BUILDER", "LISTENING_PICK", "MEANING_BLITZ", "WHACK_A_MOLE", "WORD_STACK", "WORD_TETRIS"] as const;
export type GameMode = (typeof GAME_MODES)[number];
