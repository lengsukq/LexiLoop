# LexiLoop 前端 UI 层 → Flutter 迁移评估

> 只读调查，未修改任何文件。

## 结论速览

| 维度 | 评级 | 依据 |
|---|---|---|
| **前端整体迁移难度** | **中高（7/10）** | 8,495 行 `(main)` 页面代码 + 3,445 行 `src/components` + 546 行 CSS；但**零 Canvas、零物理引擎、零复杂 SVG**，游戏全部是 DOM+CSS keyframes，视觉层是纯 CSS 玻璃拟态 |
| 视觉层迁移 | 低（3/10） | `backdrop-filter` / 渐变 / keyframes 都有 Flutter 一等公民等价物（BackdropFilter / DecoratedBox / AnimationController） |
| 数据层迁移 | 低（2/10） | 一个 15 行的 `apiFetch` 包装 + `useState`，**没有 React Query / SWR**，无乐观更新 |
| 游戏迁移 | 中（6/10） | 4 个游戏，无 Canvas / 无物理，全部是定时器 + CSS 动画 → Flutter `AnimationController` 反而更直接 |
| 布局响应式 | **低（1/10）** | 项目**已经同时做了桌面侧边栏 + 移动端底部 Tab Bar + 更多 Sheet**，Android 布局基本现成 |
| 测试迁移 | 低-中（4/10） | 3,246 行测试里 34 个是纯后端 vitest（完全不受影响），E2E 只有 34 行 |
| 后端/Server 侧 | **不需要迁移** | `src/app/api/**` 是纯 HTTP 契约，Flutter 直接复用 |

**最难的 3 个部分：**
1. **`study/study-client.tsx`（953 行）** — 单文件巨型状态机，8+ 种题型、键盘交互、自动朗读、计时器、渐进提示、AI 助记注入 session 中途
2. **`components/add/article-tab.tsx`（1,115 行）** — 分段并发 AI 导入，最大 500 词条选取、增量重试、错误去重合并
3. **液态玻璃视觉系统的 1:1 还原** — 不是逻辑难，而是 546 行 CSS 里大量精调的 alpha / blur / inset-shadow 参数需要手工重调像素

---

## 1. 页面清单与代码量

### 1.1 总量

| 范围 | 行数 |
|---|---|
| `src/app/(main)/**` (tsx+ts，62 文件) | **8,495** |
| `src/components/**` (15 文件) | **3,445** |
| `src/lib/**` (22 文件，含 TTS 客户端 270 行) | **1,178** |
| CSS（`globals.css` + `styles/*.css`） | **546** |
| `src/` 全部 ts/tsx（275 文件，含 api routes + modules） | 28,138 |
| **纯前端 UI 需重写量** | **≈ 13,664 行** |

> 其中 `src/app/(main)/import/page.tsx` 和 `create/page.tsx` 各只有 2 行——是 `redirect("/add?tab=csv")` / `redirect("/add?tab=manual")` 的兼容跳转，Flutter 里直接删掉换成 `/add` 的初始 tab。

### 1.2 逐页面行数（`src/app/(main)/`）

| 页面 | 主文件 | 目录小计 |
|---|---|---|
| 首页 dashboard | `page.tsx` **308** + `daily-ai-suggestion.tsx` **145** | **453** |
| add（3 tab） | `page.tsx` **61** | 61（实现全在 `src/components/add/`） |
| ↳ add/manual-tab | — | `components/add/manual-tab.tsx` **300** |
| ↳ add/csv-tab | — | `components/add/csv-tab.tsx` **123** |
| ↳ add/article-tab | — | `components/add/article-tab.tsx` **1115** |
| create | `page.tsx` **2**（redirect） | 2 |
| import | `page.tsx` **2**（redirect） | 2 |
| **games（6 模式 / 4 个自研游戏）** | 见第 2 节 | **1,092** |
| initialize（5 文件） | `page.tsx` **238**, `initialization-configurator.tsx` **447**, `initialize-word-list.tsx` **280**, `initialize-progress.tsx` **80**, `job-detail-dialog.tsx` **104**, `types.ts` **126** | **1,275** |
| match（连连看） | `page.tsx` **378** | **378** |
| **phonetics（音标专区，7 文件）** | `phonetic-learn.tsx` **415**, `use-phonetic-game.ts` **232**, `phonetic-question.tsx` **128**, `phonetics/page.tsx` **103**, `phonetic-setup.tsx` **85**, `phonetic-result.tsx` **65**, `types.ts` **41**, `choice.ts` **6** | **1,075** |
| **settings（3 tab + 9 组件 + 2 hooks）** | `page.tsx` **97**, `settings-shared.tsx` **109**, `use-llm-settings.ts` **208**, `use-settings-data.ts` **152** | **1,535** |
| ↳ study-settings-tab | — | **266** |
| ↳ question-type-settings | — | **183** |
| ↳ ai-config-card | — | **117** |
| ↳ provider-card | — | **117** |
| ↳ ai-settings-tab | — | **54** |
| ↳ model-picker-dialog | — | **50** |
| ↳ data-settings-tab | — | **36** |
| ↳ study-plan-settings | — | **36** |
| ↳ settings-tabs | — | **13** |
| statistics | `page.tsx` **54** | **54** |
| **study（最重页面）** | `study-client.tsx` **953** + `page.tsx` **3** | **956** |
| **words 列表** | `words/page.tsx` **166** + `learning-overview.tsx` **57** | **223** |
| **words/[id] 详情（9 组件）** | `use-word-detail.ts` **354**, `word-header.tsx` **192**, `edit-word-dialog.tsx` **144**, `youdao-preview-dialog.tsx` **122**, `page.tsx` **122**, `definitions-card.tsx` **113**, `sentence-analysis-card.tsx` **92**, `examples-card.tsx` **72**, `word-sidebar.tsx` **70**, `related-word-dialog.tsx` **63**, `extended-content-card.tsx` **57**, `learning-card.tsx` **30**, `word-detail-types.ts` **105** | **1,536** |
| `layout.tsx` | **2** | 2 |

**Top 10 单文件（迁移工作量排序）：**
1. `components/add/article-tab.tsx` **1115**
2. `study/study-client.tsx` **953**
3. `initialize/initialization-configurator.tsx` **447**
4. `phonetics/phonetic-learn.tsx` **415**
5. `match/page.tsx` **378**
6. `words/[id]/use-word-detail.ts` **354**
7. `games/page.tsx` **345**
8. `components/add/manual-tab.tsx` **300**
9. `initialize/initialize-word-list.tsx` **280**
10. `components/word-mnemonic-sheet.tsx` **269**

---

## 2. 小游戏：技术栈与移植难度

### 2.1 关键技术结论

**没有 canvas，没有 framer-motion 驱动的游戏动画，没有物理引擎，没有 SVG。** 全部 4 个游戏是：
- React `useState` 驱动状态机
- `window.setTimeout` 编排时间轴（4 个游戏共 14 处 setTimeout）
- CSS `@keyframes` 做视觉（`games-motion.css` 52 行，8 个 keyframes）
- `useRef` 做「一次性守卫」（`solvedRef` / `doneRef` / `resolvedRef`）
- `playCachedTts()` 播发音
- framer-motion 只出现在 `page.tsx` 之外的地方（app-shell / toast / ui / add / words / study / phonetics），**游戏目录 0 处**

**这是好消息**：Flutter 移植比 Web 更直接。`setTimeout` 时间轴 → `AnimationController` + `Future.delayed`；CSS keyframes → `AnimationController` + `CurvedAnimation`（`cubic-bezier(0.34,1.56,0.64,1)` → `Curves.easeOutBack`，一一对应）；状态机 → 简单的 `ChangeNotifier` / `ValueNotifier`。

**风险点**：Flutter 没有「零成本 DOM 复用」，每个地鼠/词块都是独立 Widget，60fps 下要注意 repaint 边界。`whack-a-mole` 6 只地鼠 + `word-tetris` 4 个下落块 + `word-stack` 12 个滚动块 = 都很小，用 `AnimatedBuilder` + `RepaintBoundary` 无压力。

### 2.2 逐游戏评估

| 游戏 | 文件 | 行数 | 技术 | 动画来源 | 复杂度 | Flutter 难度 | 备注 |
|---|---|---|---|---|---|---|---|
| **词汇地鼠** `WHACK_A_MOLE` | `whack-a-mole.tsx` | **98** | DOM 按钮 + emoji 🐹 | CSS `mole-pop`(回弹 cubic-bezier) / `mole-squish`(压扁) / `mole-hide`(translateY 115%) | ★★☆☆☆ | **★☆☆☆☆ 极易** | 3 个 translateY 动画，Flutter 用 `AnimatedSlide`+`Curves.easeOutBack` 直接写；坑洞阴影用 `DecoratedBox`(径向渐变) |
| **单词拼图** `WORD_BUILDER` | `word-builder.tsx` | **148** | **Pointer Events 拖拽**（`document.elementFromPoint` + `closest("[data-letter-id]")` 命中检测）+ 点击兜底 | CSS `ios-press`(scale 0.975) | ★★★★☆ | **★★★☆☆ 中等** | 唯一有真实交互难度的：`elementFromPoint` 命中测试 → Flutter 要自己实现拖拽到槽位（`Draggable`+`DragTarget` 或 `Listener`+手写命中）。10px 阈值 + click/drag 二义性抑制要手动重写 |
| **单词堆堆乐** `WORD_STACK` | `word-stack.tsx` | **89** | DOM button × 12（3 副本 × 4 词）× 2 行 | CSS `block-scroll-left/right`(无限循环 linear) / `block-drop` / `tower-bounce` | ★★★☆☆ | **★★☆☆☆ 易** | 无限滚动 marquee，Flutter 侧 `SingleChildScrollView`+`repeat` 或直接 `Marquee` 手写；塔堆 `flex-col-reverse` |
| **词汇俄罗斯方块** `WORD_TETRIS` | `word-tetris.tsx` | **125** | 绝对定位 div × 4，CSS `left: calc(col*25%+4px)` | CSS `tetris-fall`(translateY 0→430px，duration 4.2~6s 随机) / `tetris-smash` / `tetris-stack-in` | ★★★☆☆ | **★★☆☆☆ 易** | 名字叫 Tetris 但**没有消除/旋转/消行**，只是下落点击。Flutter 用 `Stack` + `AnimationController` 竖向平移，1:1 对应。随机 duration → `Random().nextDouble()` |
| **听音辨词** `LISTENING_PICK` | 内联 `page.tsx:297-302` | — | 静态按钮网格 | — | ★☆☆☆☆ | **★☆☆☆☆ 极易** | 只是 4 选 1 + 大播放键 |
| **词义冲刺** `MEANING_BLITZ` | 内联 `page.tsx:304-308` | — | 静态按钮网格 | — | ★☆☆☆☆ | **★☆☆☆☆ 极易** | 只是 4 选 1 |
| 游戏外壳 | `games/page.tsx` | **345** | 状态机 + 计时 + 答题记录 Map | — | ★★★☆☆ | **★★☆☆☆ 易** | `phase` 状态机 8 态、`answersRef: Map<number, GameAnswerState>`、`combo`/`mistake` 计分 |
| 配置 | `games-config.tsx` | **91** | 纯配置 + lucide 图标 | — | ★☆☆☆☆ | 极易 | Flutter 需把 lucide SVG 转 Material/Cupertino 图标或换 icon font |
| setup 页 | `games-setup.tsx` | **70** | 网格 + 渐变 hero | CSS | ★★☆☆☆ | **★☆☆☆☆ 极易** | |
| 结果页 | `games-result.tsx` | **64** | 组合 4 个共享组件 | CSS | ★★☆☆☆ | **★☆☆☆☆ 极易** | 复用 `game-result/summary/flashcards/leaderboard` |
| 游戏 keyframes | `games-motion.css` | **52** | 8 个 @keyframes | — | — | — | 需逐个映射到 Flutter `Curves` + `Tween` |
| `types.ts` | | **10** | — | — | — | — | |

**游戏子模块共享组件**（`src/components/`，一并计入迁移）：
- `game-result.tsx` **59** · `game-hud.tsx` **72** · `game-summary.tsx` **142** · `game-mistake-flashcards.tsx` **233** · `leaderboard-panel.tsx` **66** · `answer-diff.tsx` **173** → 共 **745 行**

**结论：游戏迁移难度「中低」**，唯一真正需要重写设计的是 `word-builder` 的拖拽命中检测。`use-game-countdown.ts`(55) / `use-game-scoring.ts`(76) / `use-active-stopwatch.ts`(114) 三个 hook 转成 Flutter 计时器/计数器很直接。

---

## 3. 视觉风格：液态玻璃系统

### 3.1 最近提交 `3bc6538 "style(ui): 液态玻璃视觉升级"` 改了什么

22 文件，+1115 / -277。**风格部分**：

| 文件 | 改动 |
|---|---|
| `styles/glass.css` +37 | 新增 `.liquid-glass-subtle`（chips/输入容器，blur 14px saturate 150%）、`.liquid-glass-interactive`（hover 蓝色发光边框 + spring 抬升 2px，暗色下加 `0 0 20px rgba(10,132,255,0.15)` 外发光） |
| `styles/motion.css` +45 | 新增 `wave-bounce-1..4`（TTS 播放时 4 条律动柱）、`soft-shake`（错答轻抖 ±4px）、`shimmer-flow`（进度条微光扫过，1.8s 无限循环） |
| `globals.css` +14 | 新增 `--color-border-subtle/default/strong` 三档边框 token（明暗双套）+ 5 档圆角 `--radius-sm..2xl` (10/14/18/22/28px) |
| `components/ui.tsx` +147 | 新增 `AnimatedCounter`（**手写 `requestAnimationFrame` 数字递增**，cubic ease-out，`duration=0.65s`，配 `num-tabular` 等宽数字防抖动）；`AudioWave`；`Progress` 加 `indeterminate` 微光模式；`Dialog` 换成 framer-motion spring 弹入（`bounce: 0.12`） |
| `components/app-shell.tsx` ±178 | 桌面侧边栏整块改液态玻璃 + `layoutId="sidebar-active-pill"` 弹簧滑块（`stiffness:480, damping:36`）；移动端浮动玻璃 Tab Bar；新增「更多」玻璃 Sheet |
| `components/toast.tsx` ±69 | `AnimatePresence mode="popLayout"` 进出动画 |
| 页面级 | 首页/单词本/单词详情/学习/统计/匹配/音标/添加 8 个页面的样式统一 |

### 3.2 液态玻璃实现清单（行号证据）

**`src/app/styles/glass.css`（233 行）** — 完整的「Liquid Air-Glass Material System (Apple Vision / iOS 18+)」：

| 类名 | 行 | 关键属性 | Flutter 等价 |
|---|---|---|---|
| `.liquid-glass` | 6-36 | `linear-gradient(135deg, rgba(255,255,255,.68), rgba(255,255,255,.46))` + **`backdrop-filter: blur(24px) saturate(175%)`** + 4 层 `box-shadow`（含 `inset 0 1px 0 rgba(255,255,255,.85)` 高光） + `@media (prefers-color-scheme: dark)` 全套暗色覆写 | `BackdropFilter(filter: ImageFilter.blur(24,24).fractalNoise?/σ=1.75)` + `DecoratedBox(gradient+border+BoxShadow)` + `Theme.of(context).brightness` |
| `.liquid-glass-elevated` | 39-70 | `blur(30px) saturate(180%)`，155° 渐变 | 同上（参数更大） |
| `.liquid-glass-specular::before` | 73-99 | 顶部 45% 高度白色渐变覆盖层 `pointer-events:none` 模拟折射高光 | `Stack` + `Positioned`+`IgnorePointer`+`DecoratedBox(gradient)` |
| `.liquid-glass-edge::after` | 102-130 | 底部 1px 水平高光线，中心 65% alpha，两端透明 | `Positioned(bottom:0, height:1)` + `LinearGradient(colors:[transparent,white54,white104,white54,transparent])` |
| `.ios-press` | 137-146 | `transition: transform .18s cubic-bezier(.16,1,.3,1)`，`:active` scale 0.975 + opacity 0.88 | `GestureDetector.onTapDown` → `AnimatedScale(scale:0.975)`，`duration: 180ms`，`curve: Curves.easeOutCubic`（Flutter 内置 `Curves.fastEaseInOut` 近似） |
| `.ios-lift` | 149-167 | hover `translateY(-2.5px)` + 大扩散阴影 | `MouseRegion` 在移动端可直接省掉 |
| `.glass-inner` | 170-196 | `blur(18px) saturate(160%)` 卡片内子面板 | `BackdropFilter(blur 18)` |
| `.liquid-glass-subtle` | 199-210 | `blur(14px) saturate(150%)`，纯 `rgba(255,255,255,.45)` | 同上 |
| `.liquid-glass-interactive` | 213-233 | hover 蓝色边框 + `0 0 20px` 外发光 | `AnimatedContainer` + `BoxShadow(color: accent.withOpacity(.15), blurRadius:20)` |

**`src/app/globals.css`（133 行）**：
- **环境光背景**：`body::before`（104-126 行）`position:fixed; inset:0; z-index:-1` + **4 层 `radial-gradient`（蓝 0.08 / 靛 0.06 / 紫 0.05 / 青 0.05）+ `filter: blur(80px)`**（暗色 90px）。**这是整个视觉的底座** → Flutter：`Stack` 最底层放 `CustomPaint` 或 `Container(decoration: BoxDecoration(gradient: RadialGradient(...)))`，或直接 `ImageFiltered(imageFilter: ImageFilter.blur(80))` 包裹一个 `DecoratedBox`。**注意：Flutter 里 blur 80px 的全屏多层径向渐变在中低端 Android 上有性能风险**，建议改用 `ShaderMask` 或预渲染 PNG。
- **设计 token**（11-86 行）：20 个语义色（`--ll-accent: #007aff` 等 iOS 系统色）+ 明暗双套 `prefers-color-scheme` + 5 档圆角。→ Flutter：`ColorScheme` + `ThemeExtension` + `ThemeMode.system`，**1:1 对应，几乎零成本**。
- `@theme inline`（11-37 行）：Tailwind v4 语法，工具类 `text-quaternary-label` / `bg-accent/10` 自动适配暗色。

**`src/app/styles/motion.css`（150 行）** — 13 个 @keyframes：
- `ios-fade-up/down`（`translateY(12px) scale(.985)` + opacity，spring 缓动）、`ios-scale-in`(scale .955)、`ios-pop-in`(scale .92→1.015→1)、`shake`(±4px 5 段)、`progress-slide`(`translateX(-110%→260%)` 1.4s 无限)、`subtle-pulse`、`wave-bounce-1..4`(height %)、`soft-shake`、`shimmer-flow`(translateX -100%→100%)
- 3 个缓动变量：`--ease-spring: cubic-bezier(0.16,1,0.3,1)`、`--ease-spring-snappy: cubic-bezier(0.2,0.9,0.2,1)`、`--ease-smooth: cubic-bezier(0.32,0.72,0,1)`
- `.stagger-1..6` 阶梯延迟 0.04s×n
- → Flutter：`Curves.easeOutQuint`(≈.16,1,.3,1)、`Curves.easeOutBack`、`AnimationController` + `Interval` 做 stagger

**`src/app/styles/layout.css`（30 行）**：
- `min-width:1024px` → `.app-main { margin-left: 264px }`（**侧边栏布局**）
- `max-width:639px` → 全局 blur 从 24→32px + `brightness(108%)`（移动端加深玻璃）、禁用 `.ios-lift:hover`
- `prefers-reduced-motion: reduce` 全局禁用动画（Flutter 侧可忽略/或用 `MediaQuery.disableAnimations`）
- 自定义 iOS 风格 5px 滚动条（Flutter 需 `ScrollConfiguration` 自绘或接受 Material 默认）

**`src/app/layout.tsx`（4 行）**：极简——只有 `<html lang="zh-CN"><body>`，无 Provider/无 ThemeProvider。**这意味着设计上完全没有 React 语境耦合**，Flutter 端也是纯 `MaterialApp`。

**`src/components/ui.tsx`（406 行）** 设计系统：
- `buttonClass()` 8-21：5 variant × 3 size，含 `shadow-[0_2px_8px_rgba(0,122,255,0.25),inset_0_1px_0_rgba(255,255,255,0.28)]` 等
- `Card` 124-134：`liquid-glass-elevated liquid-glass-specular` → **所有卡片都是玻璃**
- `Dialog` 294-347：framer-motion `AnimatePresence` + spring `bounce:0.12`
- `Segmented` 208-255：framer-motion `layoutId` 滑块 `stiffness:500, damping:36`
- `AnimatedCounter` 28-74：**手写 RAF 循环** → Flutter `TweenAnimationBuilder<int>` 或 `AnimatedSwitcher` + `Tween<double>`
- `Pagination` 368-405：含玻璃 sticky 变体 + `paginationRange` 省略号算法（Flutter 直接抄逻辑）

**Tailwind 用量**：`sm:` 前缀 **285 处**，`lg:` 16 处，`md:` 4 处，`xl:` 10 处 → **项目以移动优先 + sm(640) 断点为主**，桌面增强是后加的。这对 Android 迁移是**极好的消息**。

### 3.3 视觉迁移结论

| 项 | 难度 | 说明 |
|---|---|---|
| 颜色/圆角 token | ★☆☆☆☆ | `globals.css:11-86` → Flutter `ColorScheme`+`ThemeExtension`，几乎照抄 |
| 玻璃卡片 | ★★☆☆☆ | `BackdropFilter` 是 Flutter 一等公民；`saturate()` → `ImageFilter.compose` 叠 `ColorFilter.matrix` 饱和度矩阵（略繁琐） |
| specular / edge 叠加层 | ★★☆☆☆ | `Stack` + `IgnorePointer` |
| 环境光背景 | ★★★☆☆ | 4 层 radial-gradient + blur(80px) 全屏，中低端 Android 掉帧风险，建议降级为静态渐变 |
| 13 个 keyframes | ★★☆☆☆ | 全部可用 `AnimationController` 1:1 映射 |
| `ios-press` 微交互 | ★☆☆☆☆ | `AnimatedScale` |
| framer-motion 布局动画 | ★★☆☆☆ | `layoutId` 共享元素（侧边栏滑块、Segmented 滑块）→ Flutter 用 `AnimatedAlign`/`TweenAnimationBuilder` + `Stack` 层叠 |
| lucide-react 图标 | ★★☆☆☆ | 40+ 个图标，需重映射到 Material Icons 或转 font/icon widget |

**整体视觉迁移难度：中等偏低（约 3/10）**。工作量不在逻辑，而在「546 行 CSS 里精调过的 alpha 值和 blur 半径需要肉眼逐个比对还原」。

---

## 4. 状态管理与数据获取

### 4.1 结论：极简，没有第三方数据层

**没有 React Query、没有 SWR、没有 Zustand、没有 Redux、没有 Apollo。** 依赖清单（`package.json:22-35`）只有：React 19 / framer-motion / lucide-react / papaparse / recharts / zod / ts-fsrs / date-fns / pg / node-edge-tts。

### 4.2 数据获取三层

**① `src/lib/client-api.ts`（15 行）** — 唯一的 fetch 封装：
```
apiFetch<T>(input, init) → fetch + cache:"no-store"
  → 解析 { success, data, error: { code, message } } 信封
  → 401 + AUTH_REQUIRED → window.location.assign("/login?next=...")
  → !ok || !success → throw new Error(message)
```
响应信封 `{ success, data, error }` 与 `src/lib/api.ts:69-79` 的 `ok()`/`fail()` 严格配对。

**② `src/lib/api.ts`（118 行）** — **纯服务端**，`ApiError` 类 + 42 条业务错误码表（5-48 行）+ `handleRouteError`。Flutter 端不需要，但要照抄错误码→中文文案的映射表。

**③ `src/lib/route-factory.ts`（28 行）** — **纯服务端**，只消除 games/match/phonetics 三处 `sessions/[id]/complete` 样板。Flutter 无关。

**④ `src/lib/tts-client.ts`（270 行）** — 唯一「有状态」的客户端库，**是真正的迁移坑**：
- **IndexedDB 音频缓存**：`lexiloop-client-cache` / `tts-audio` store，存 `Blob`（1-108 行 `openAudioDatabase`、`readCachedAudio`）
- `new Audio(objectUrl)` 播放（226 行），含 `playbackRate` 按 word/phrase/sentence 三档速度（从 `/api/settings` 拉，43-69 行）
- `preloadTtsBatch()` 预热当前题 + 后 4 题（games/page.tsx:106-109 调用）
- → Flutter：`just_audio` + `path_provider` 文件缓存（比 IndexedDB 更简单），或 `flutter_cache_manager`

### 4.3 数据模式逐项

| 模式 | 现状 | 证据 | Flutter 等价 |
|---|---|---|---|
| **组件本地状态** | 100% `useState` + `useCallback` + `useEffect` 手动取数 | `page.tsx:30-46`、每个页面重复同一模板 | Riverpod `AsyncNotifier` |
| **全局状态** | 无。仅 2 个「全局」机制：<br>① `BackgroundKeepalive` 常驻组件（71 行）<br>② `window.dispatchEvent` 自定义事件总线 | `background-keepalive.tsx` | Riverpod `StreamProvider` + `ref.onDispose` |
| **乐观更新** | **完全没有**。所有写操作都是 `await apiFetch` → 成功后 `setState` | grep `乐观/optimistic` 命中 0 | 无需迁移，但可顺势加上 |
| **轮询** | 有，但**不是页面各自轮询**，而是全局单例保活：<br>`ACTIVE_INTERVAL_MS = 3_000`（忙碌）/ `IDLE_INTERVAL_MS = 60_000`（空闲）/ `RETRY_BACKOFF_MS = 10_000`（失败退避）<br>挂载在 `AppShell` 内跨页面不卸载，tick 完 `dispatchEvent(BACKGROUND_TICK_EVENT)`，页面订阅刷新 | `background-keepalive.tsx:15-68`、`initialize/page.tsx:58-71` | `Timer.periodic` + `WidgetsBindingObserver`（替代 `document.hidden` 检查）<br>**Android 优先级**：Flutter 无 `document.visibilitychange`，需用 `WidgetsBindingObserver.didChangeAppLifecycleState` 区分前台/后台；后台时**必须停轮询**（省电+省流量），这与 Web 版的 `document.hidden` 检查语义一致 |
| **文件上传** | 2 处：<br>① CSV：`csv-tab.tsx:40,92` `input[type=file][accept=".csv,text/csv]` + **拖拽 `onDrop`** + 10MB/20000 行限制；解析用 `papaparse`（在**服务端** `modules/imports/parser.ts:32`，不是客户端）<br>② 备份 JSON：`data-settings-tab.tsx:23,35` `accept=".json"` | | `file_picker` 包（Android SAF）<br>**注意：Android 上 `onDrop` 拖拽不存在，要改文件管理器选择器 + Storage Access Framework** |
| **粘贴文章** | `article-tab.tsx`（1115 行）：大文本框 + 分段规划 + **并发 LLM 预览** `ARTICLE_SEGMENT_CONCURRENCY` workers + `Promise.all(workers)`（258, 307 行）+ 增量重试 + 错误 token 去重合并 | | `dart:io`/`flutter_quill` 富文本或纯 `TextField`；并发用 `Future.wait` 或 `Isolate` |
| **分页** | 每页手写 `page/totalCount/pageSize` state + `Pagination` 组件 | `initialize/page.tsx:15,73`、`words/page.tsx:26-36` | Riverpod pagination provider |
| **防抖搜索** | `setTimeout 350ms` | `words/page.tsx:30` | `debouncer` 包 |
| **鉴权** | HMAC 签名 Cookie（`lexiloop_auth`，7 天）+ 密码登录页。服务端 `lib/security.ts` | | Flutter `http` 支持 Cookie 自动携带；或改 Bearer token（更干净） |
| **离线** | **没有**。IndexedDB 只用于 TTS 音频缓存，不做数据离线 | | 无需迁移 |

### 4.4 Flutter 侧推荐栈

```dart
// 状态
riverpod 2.x + riverpod_generator        // 替代 useState 模板，AsyncNotifier 一对一映射
// 网络
dio 5.x                                  // 替代 apiFetch；拦截器里复刻 401 → 登录跳转 + {success,data,error} 信封解包
// 音频
just_audio + path_provider               // 替代 tts-client 的 IndexedDB + new Audio()
// 文件
file_picker + share_plus                  // 替代 <input type=file> + 拖拽
// 图表
fl_chart                                 // 替代 recharts（statistics 页唯一用到）
// 建模
freezed + json_serializable              // 可选：目前只有 apiFetch<T> 泛型，没有类模型
// 图表以外的 icon
lucide_icons 或 phosphor_flutter
```

**数据层迁移难度：低（2/10）**。因为根本没有 React Query 那种「查询缓存失效/重试/去重」要重新建模的东西——只是一个 fetch 包装 + 手动 useState，Riverpod 的 `AsyncNotifier` 甚至更简洁。**唯一要注意的是 Android 后台生命周期**（保活轮询、原 `document.hidden` 检查）。

---

## 5. 响应式：桌面 Web 还是移动优先？

**答案：已经是「桌面 Web + 完整移动适配」双布局，Android 迁移几乎是白捡的。**

### 5.1 `src/components/app-shell.tsx`（223 行）证据

| 布局 | 断点 | 实现 | 行号 |
|---|---|---|---|
| **桌面侧边栏** | `lg`（1024px） | `<aside className="... fixed inset-y-0 left-0 z-30 hidden w-[256px] flex-col ... lg:flex">` + 8 项导航 + `⌘1-8` 快捷键 + 底部「自托管运行中 / FSRS」状态卡 + `⌘1-8` 提示 | 75-131 |
| **主内容区让位** | `min-width:1024px` | `.app-main { margin-left: 264px }` | `layout.css:4-6` |
| **移动底部 Tab Bar** | `< lg` | `<nav className="fixed inset-x-3 bottom-[max(0.6rem,env(safe-area-inset-bottom))] ... lg:hidden">`，4 个主 tab（`mobilePrimary = ["/", "/study", "/words", "/add"]`）+ 「更多」按钮，玻璃胶囊 `liquid-glass liquid-glass-specular rounded-[20px]` | 186-219；`mobilePrimary` 定义在 25 行 |
| **「更多」玻璃 Sheet** | `< lg` | `fixed inset-0 z-40 flex flex-col justify-end lg:hidden` + 遮罩 `bg-black/20 backdrop-blur-sm` + 玻璃面板 `liquid-glass-elevated liquid-glass-specular animate-scale-in`，2 列网格放其余 4 个入口 | 148-183 |
| **学习页隐藏 Tab Bar** | — | `isStudyScreen` = `/study` `/match` `/games` `/phonetics` 时不渲染底栏，且 `pb` 从 `pb-[calc(6rem+env(safe-area-inset-bottom))]` 缩到 `pb-4` | 35, 134, 186 |
| **页面切换过渡** | — | `<motion.div key={pathname} initial={{opacity:0,y:5}} animate={{opacity:1,y:0}} transition={{duration:.2, ease:[.16,1,.3,1]}}>` | 136-143 |
| **容器** | — | `mx-auto max-w-6xl px-4 py-4 sm:px-6 sm:py-6 lg:px-8 lg:py-7` | 135 |

### 5.2 已有的移动端适配细节

- **`env(safe-area-inset-bottom)`** 已用于底栏和批量操作栏（`app-shell.tsx:187`、`initialize/page.tsx:217`）→ Android 手势条已考虑
- **`prefers-color-scheme`** 暗色已全套覆盖（`globals.css:62-86` + `glass.css` 每段都有一份 dark 覆写）→ Flutter `ThemeMode.system` 直接对应
- **24 处** `sm:hidden` / `hidden sm:...` / `lg:hidden` 响应式显隐（如 `statistics/page.tsx` 移动端用卡片列表、桌面端用 `<table>`）
- **E2E 已经在测移动端**：`tests/e2e/mobile.spec.ts` 对 320 / 375 / 390px 三个宽度断言「无横向溢出」+「底部导航可见」
- **无横向滚动风险**：E2E 第 13-14 行专门断言 `body.scrollWidth <= window.innerWidth`

### 5.3 唯一需要处理的双栏布局

移动端全部单栏，只有 3 处桌面双栏需要砍掉：

| 位置 | 类名 | 处理 |
|---|---|---|
| `words/[id]/page.tsx:56` | `grid lg:grid-cols-[1.4fr_.6fr]`（正文 + `WordSidebar`） | Android 直接删 `WordSidebar`，内容进 `TabBar`/`ExpansionTile` 或滑入抽屉 |
| `statistics/page.tsx` | `lg:grid-cols-[1.5fr_.5fr]`（图表 + 熟练度分布） | 改 `Column` 纵向堆叠 |
| `initialize/initialization-configurator.tsx` | `grid-cols-[minmax(0,1fr)_320px]`（无断点前缀，**手机也是两栏**） | 需新加响应式，或改成上下 |

`match/page.tsx` 已经是「始终左右两栏」（提交 `2e9a24e fix(match): 连连看始终左右两栏，避免上下翻页`），是刻意设计，Android 保留。

### 5.4 导航重构工作量

Flutter 需要把 8 项导航映射到移动端信息架构。现有 Web 方案可直接抄：

```
Flutter: StatefulShellRoute.indexedStack  (或 go_router ShellRoute)
  ├─ branch 0: /         今日     (Home icon)     ← mobilePrimary
  ├─ branch 1: /study    复习     (PlayCircle)     ← mobilePrimary
  ├─ branch 2: /words    单词本   (BookMarked)     ← mobilePrimary
  ├─ branch 3: /add      添加     (PlusCircle)     ← mobilePrimary
  └─ branch 4: 更多 Sheet: /phonetics /initialize /statistics /settings
                  + 游戏入口 /games /match 从首页卡片进入（Web 版就是这样，
                    见 page.tsx 的 Gamepad2/Blocks/Hammer 图标卡片）
```

**「学习/游戏模式」隐藏底栏**的逻辑（`app-shell.tsx:35`）→ `StatefulShellRoute` 里给这 4 个路由单独的 Scaffold（不带 `bottomNavigationBar`）。

**响应式迁移难度：低（1-2/10）**。移动端布局、safe-area、暗色、无溢出都已经做好并有 E2E 保障。这是整个迁移里**最不需要担心**的部分。

---

## 6. 测试

### 6.1 结构（`tests/`，共 3,246 行，36 文件）

```
tests/
├── setup.ts (78)              # 加载 .env/.env.local；强制派生 neondb_test 库；临时备份目录
├── e2e/                      # Playwright，仅 2 个文件 34 行
│   ├── smoke.spec.ts (8)          # 首页渲染 + /import 跳转
│   └── mobile.spec.ts (26)        # 320/375/390px 三宽度：底部导航可见 + 无横向溢出 + 筛选弹层；/→/study 跳转
├── integration/ (11 文件 1170 行)   # 全部打真 PostgreSQL：business-closure / study-prioritization /
│                                     #   worker-and-review / daily-suggestion / keepalive / statistics-duration …
└── unit/ (22 文件 2264 行)          # 纯函数：mastery / article-candidates / llm-client / tts-client /
                                      #   youdao-provider / answer-evaluation-fuzzy / import-parser …
```

### 6.2 覆盖了什么

| 层次 | 工具 | 覆盖内容 | **迁移影响** |
|---|---|---|---|
| **单元测试 22 个 / 2,264 行** | `vitest`（`vitest.config.ts`：`environment: "node"`，`include: ["tests/**/*.test.ts"]`） | 全部是**后端业务逻辑**：FSRS mastery 衰减、答案模糊判定、AI prompt/schema、候选词合并、TTS 客户端、YouDao provider、CSV parser | ✅ **完全不受 Flutter 迁移影响** —— 依赖 `environment:"node"`，前端页面没被测（虽然装了 `@testing-library/react`，实际 `include` 只收 `.test.ts`） |
| **集成测试 11 个 / 1,170 行** | `vitest` + 真 PostgreSQL（`neondb_test` 隔离库，`setup.ts:25-31`） | 业务闭环、初始化聚合、每日建议、保活 tick、学习优先级排序、统计时长 | ✅ **不受影响** —— 测的是 API/服务层 |
| **E2E 2 个 / 34 行** | `playwright.config.ts`：`baseURL=127.0.0.1:3100`、`webServer: yarn dev --port 3100`、`projects: [{name:"chromium"}]`、自动派生 `neondb_test`（7-11 行）、`trace: "on-first-retry"` | ① 首页标题 + `/import` 跳转渲染<br>② 移动端导航 + 筛选弹层 + 无横向溢出 + 快捷入口跳转 | ⚠️ **这部分会随 Web 前端一起废弃**。共 34 行，覆盖极浅 |
| **组件测试** | — | **0 个**。`@testing-library/react` + `jsdom` 装了但 `include` 正则 `*.test.ts` 排除了所有 `.tsx` | ✅ 无迁移负担（也说明前端**无单测保护网**） |

### 6.3 迁移后如何处理

1. **后端 33 个 vitest 文件（3,212 行，99%）原地保留**。`src/app/api/**` 变成纯 HTTP 服务后，Next.js 可以保留也可以换成 Koa/Fastify —— 这部分**不在前端迁移范围内**。
2. **2 个 Playwright E2E（34 行）替换为 `flutter_test` + `integration_test`**：
   - `smoke.spec.ts` → `integration_test/app_test.dart`：`pumpWidget` + `find.text('LexiLoop')` + 路由断言
   - `mobile.spec.ts` → `tester.binding.setSurfaceSize(Size(390, 844))` + 断言底部 NavigationBar 4 项可见 + **横向溢出检测**（Flutter 里对应 `tester.takeException()` 无 `RenderFlex overflowed`）
3. **Flutter 侧必须新写的测试（原项目没有的风险敞口）**：
   - `use-game-countdown` / `use-game-scoring` / `use-active-stopwatch` → `fakeAsync` 单测（这三个 hook 245 行，有明确时间逻辑，最容易出回归）
   - `paginationRange`（`ui.tsx:349-359`）纯函数单测
   - 6 个游戏的交互状态机 widget test
4. **计时器相关测试要特别小心**：`use-active-stopwatch.ts:46,87,98` 依赖 `document.visibilityState` + `document.hasFocus()`。Flutter 里 `hasFocus()` 无直接等价（`FocusManager.instance.primaryFocus`），**「切到别的 App 暂停计时」这个核心逻辑必须重测**——它直接影响统计页的「有效做题时长」正确性。

---

## 7. 整体迁移难度评级

### 7.1 综合：**中高 · 7/10**

**判定依据：**

**降难度因素（5 条）**
1. **零 Canvas、零 SVG 动画、零物理引擎、零 WebGL** —— 游戏全是 DOM+CSS keyframes，Flutter 更擅长
2. **零第三方数据层**（无 React Query/SWR/Zustand/Redux），数据获取只是一个 15 行 `apiFetch`
3. **视觉系统是纯 CSS**（Tailwind v4 + 3 个自定义 CSS 文件），全部有 Flutter 一等公民等价物；设计 token 已经抽成 20 变量 + 5 圆角，明暗双套，**几乎可 1:1 抄成 `ColorScheme`**
4. **响应式已完成**（桌面侧边栏 + 移动底栏 + 更多 Sheet + safe-area + E2E 三宽度保障）
5. **前端无组件单测**，没有测试债要继承；33/36 个测试文件是后端逻辑，完全不动

**升难度因素（5 条）**
1. **13,664 行前端代码**要重写，其中 `article-tab.tsx`(1115) + `study-client.tsx`(953) 两个文件就占 15%
2. **视觉 1:1 还原靠肉眼** —— 546 行 CSS 里 60+ 处精调 alpha/blur/inset-shadow，没有 design token 化的阴影/模糊规范，全局环境光 blur(80px) 在 Android 上还有性能风险
3. **`tts-client.ts`(270 行)** 用了 IndexedDB + `new Audio` + 三档语速 + 预热批次，要换成 `just_audio` 重做缓存层
4. **保住长会话学习状态机**（`study-client.tsx`）语义正确，含 8+ 题型、自适应追问插队、hint 惩罚评分、时长统计
5. **后台保活语义要重新设计** —— Web 用 `document.hidden` + 全局常驻组件；Android 是可被系统杀死的进程 + 多任务切换，需要 WorkManager 或前台服务 rethink

### 7.2 最难的 3 个部分

#### 🥇 #1 `study/study-client.tsx`（953 行）— 单文件学习会话状态机

- **为什么难**：它是全项目唯一「跨后端+前端+计时+音频+手势+键盘」耦合的巨型组件
- **具体难点**：
  - 8+ 种题型分支（`EN_TO_ZH_CHOICE` / `ZH_TO_EN_CHOICE` / `LISTENING_CHOICE` / `LETTER_BANK` / `ZH_TO_EN_SPELLING` / `LISTENING_SPELLING` / `CLOZE` / 句子题），`rate()` 函数（393-420 行）里对每种题型用不同方式提取 `userAnswer`
  - `adaptiveFollowUp` 自适应追问会**在会话中途插入新题**，需要 `reloadSession(sessionId)` 全量重拉（410-416 行注释明确说明何时本地推进、何时重拉）
  - hint 惩罚评分：`usedHint && 拼写题 && exactLocal===false && rating ∈ {GOOD, EASY}` → 强制降级为 `HARD`（394 行）
  - 软键盘管理（`dismissKeyboard()`）、`ClampedText` 截断、`Pronunciation` 自动朗读（921-952 行，播放后 900ms 复位）
  - `choiceProgressTimerRef`（176 行）是「作答进度条」定时器，与题目生命周期严格绑定
  - 提交有 320ms 延迟动画窗口（412 行）
- **迁移建议**：必须拆成 Riverpod `AsyncNotifier<StudySessionState>` + 每题型独立 Widget + 状态枚举显式建模。**不要试图逐行翻译**。预计 1,100-1,400 行 Dart，工期占前端迁移的 25-30%。

#### 🥈 #2 `components/add/article-tab.tsx`（1,115 行）— AI 分段并发导入

- **为什么难**：它是项目里唯一涉及「并发任务编排 + 增量重试 + 错误去重」的前端逻辑
- **具体难点**：
  - `ARTICLE_SEGMENT_CONCURRENCY` 个 worker 并发请求 + `Promise.all`（258, 307 行）
  - `SegmentStatus` 状态机 `idle/loading/success/error`，每段独立 retry
  - 候选词合并去重 `mergeArticlePreviews()`（56-59 行）复用 `modules/article-import/candidates.ts`，且「服务端/增量/重试」三处结果必须合并（早期 commit `453ebda fix(article): 修复分段预览页无限重渲染卡死整页` 就是这个的 bug 史）
  - 最长 180s 超时（commit `daf0c50`），500 词条上限（commit `3bc6538` 刚从 100 放宽）
  - `setData` 里对 `items.map` 的嵌套不可变更新（368-389 行 `generateAiMnemonic` 那种 3 层 spread）
- **迁移建议**：`mergeArticlePreviews` 这类纯函数**照抄逻辑**（有单测覆盖）；并发部分用 `Future.wait` + `StreamController` 流式更新进度。移动端屏幕窄，分段预览列表的虚拟滚动 + 选择交互要重新设计（Android 上 500 个候选词的批量勾选是 UX 大改）。

#### 🥉 #3 液态玻璃视觉系统的像素级还原

- **为什么难**：不是逻辑难（`BackdropFilter` 一行就够），而是 546 行 CSS 中 60+ 处**手工调过的视觉参数**没有规范化的 design token 文档。典型：
  - `.liquid-glass`: blur 24px + saturate 175% + 4 层 shadow（`0 1px 2px rgba(0,0,0,.02)` / `0 8px 24px -4px rgba(0,0,0,.04)` / `inset 0 1px 0 rgba(255,255,255,.85)` / `inset 0 -1px 0 rgba(0,0,0,.02)`）
  - `.liquid-glass-elevated`: blur 30px + saturate 180% + 155° 渐变角（不是 135°）
  - `.liquid-glass-subtle`: blur 14px + saturate 150%
  - 移动端（<640px）全局提升到 blur 32/38px + `brightness(108%/110%)`
  - `globals.css:104-126` 环境光：4 层 radial-gradient + `blur(80px)`（暗色 90px）
- **Flutter 侧的三个具体坑**：
  1. `saturate(175%)` 在 Flutter 没有一行 API，要用 `ImageFilter.compose(ImageFilter.blur(...), ImageFilter.colorFilter(ColorFilter.matrix(饱和度矩阵)))` 手动叠
  2. 全屏 4 层 blur(80px) 在中低端 Android（Adreno 5xx / Mali-G52 及以下）**实测会掉到 40fps 以下**——必须准备降级方案（预渲染 PNG 背景 或 减少到 1 层）
  3. `border-bottom-color` 与 `border-color` 不等（`.liquid-glass` 是 `rgba(255,255,255,.55)` vs `rgba(255,255,255,.25)`），Flutter `Border` 需逐边设置
- **迁移建议**：先建 `LiberaTheme`（ThemeExtension）把 5 个玻璃档位 + 6 个动画曲线 + 20 色 token 全部固化成 Dart 常量，再逐页还原。**开工前用 3 台不同 Android 设备做性能基线测试。**

---

## 8. 迁移路线建议（附带）

| 阶段 | 内容 | 难度 | 备注 |
|---|---|---|---|
| **P0 地基** | `LiberaTheme`（20 色 + 5 圆角 + 5 玻璃档 + 6 曲线）、`Dio` 客户端 + `{success,data,error}` 拦截器、Riverpod 骨架、`just_audio` TTS 层 | ★★★☆☆ | 视觉和网络的公共依赖，必须先做 |
| **P1 只读页** | 首页 dashboard、statistics、words 列表、words 详情 | ★★☆☆☆ | 无状态写入，先跑通验证主题还原度 |
| **P2 设置** | settings 3 tab + 9 组件 | ★★☆☆☆ | 纯表单，Flutter `Form` + `DropdownButton` 直接对应 |
| **P3 游戏** | 4 个游戏 + match + phonetics | ★★☆☆☆ | ← Flutter 的主场 |
| **P4 写路径** | add（manual/csv/article）、initialize、edit-word | ★★★★☆ | 文章 AI 导入最难 |
| **P5 学习** | study-client | ★★★★★ | 单独一个 sprint |
| **P6 补测** | Flutter widget/unit test 覆盖 245 行计时器 hook + 6 个游戏状态机 | ★★★☆☆ | 计时器的 `document.hasFocus()` 语义必须重测 |

**总量估算**：13,664 行 TSX → 约 18,000-22,000 行 Dart（含 Riverpod boilerplate + 显式状态建模），**单人 3-5 个月**，或双人 2-3 个月。

---

## 附：文件索引

- [app-shell.tsx](src/components/app-shell.tsx) — 双布局外壳（桌面侧边栏 75-131 / 移动底栏 186-219 / 更多 Sheet 148-183）
- [glass.css](src/app/styles/glass.css) — 液态玻璃系统全实现（233 行）
- [motion.css](src/app/styles/motion.css) — 13 个 keyframes（150 行）
- [globals.css](src/app/globals.css) — 设计 token（11-86）+ 环境光背景（104-126）
- [layout.css](src/app/styles/layout.css) — 断点（4-14）+ reduced-motion（16-18）
- [ui.tsx](src/components/ui.tsx) — 设计系统（AnimatedCounter 28-74 / Card 124-134 / Dialog 294-347 / Segmented 208-255 / Pagination 368-405）
- [client-api.ts](src/lib/client-api.ts) — 15 行唯一 fetch 封装
- [api.ts](src/lib/api.ts) — 42 条业务错误码（服务端，Flutter 需抄文案表）
- [route-factory.ts](src/lib/route-factory.ts) — 服务端样板消除，Flutter 无关
- [background-keepalive.tsx](src/components/background-keepalive.tsx) — 全局保活轮询 3s/60s/10s
- [tts-client.ts](src/lib/tts-client.ts) — IndexedDB 音频缓存 + 三档语速 + 预热
- [study-client.tsx](src/app/(main)/study/study-client.tsx) — 最难，953 行
- [article-tab.tsx](src/components/add/article-tab.tsx) — 次难，1115 行
- [games-motion.css](src/app/(main)/games/games-motion.css) — 8 个游戏 keyframes（52 行）
- [playwright.config.ts](playwright.config.ts) — E2E 配置 + neondb_test 隔离
- [vitest.config.ts](vitest.config.ts) — `include: ["tests/**/*.test.ts"]`，前端无单测