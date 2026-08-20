/** 每日推荐候选排序权重。集中命名便于调参，避免 `score()` 里散落裸数字。 */
export const SUGGESTION_SCORE_WEIGHTS = {
  incorrect: 120,
  again: 75,
  hard: 38,
  wrongActive: 55,
  wrongCount: 7,
  hardCount: 4,
  dueToday: 22,
  difficulty: 2,
  lapses: 5,
  fallback: 1,
  /** 答题时长基线：低于此值不计入分数。 */
  durationBaselineMs: 7_000,
  /** 超过基线后每多少毫秒加 1 分。 */
  durationStepMs: 300,
  durationMax: 45,
  /** 逾期天数封顶与每日权重。 */
  overdueMax: 35,
  overduePerDay: 4,
} as const;
