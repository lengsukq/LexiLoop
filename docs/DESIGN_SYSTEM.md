# LexiLoop 设计系统

这份文档说明 Flutter 版的视觉体系**是什么、为什么是这样、怎么防止它退化**。
它对应旧版的 `src/app/globals.css` 与 `components/**` 里散落的样式，但不是逐条
翻译——有几处是刻意的重新设计，理由写在下面。

配套阅读：[`FLUTTER_PARITY.md`](FLUTTER_PARITY.md) 看功能对照，
[`CLEAN_CODE_BASELINE.md`](CLEAN_CODE_BASELINE.md) 看代码整洁度基线。

---

## 1. 为什么需要一份设计系统

收敛之前，「样式没统一」不是感觉，是可测量的：

| 维度 | 收敛前 | 现在 |
|---|---|---|
| 字号 | **24 种**（含 6 个半点值：10.5/11.5/12.5/13.5/14.5/15.5），399 处 | 9 档，全部带行高 |
| 圆角 | **10 种**取值（3/4/6/8/10/12/13/14/16/999），26 处 | 7 档 + `pill` |
| 间距 | **25 种**取值（1/2.5/3/5/7/9/11/18/22/28/48…） | 12 档 2pt 节奏 |
| 淡色透明度 | **21 种**（0.06/0.07/0.08 三档并存，0.10–0.16 五档并存） | 6 档 |
| 徽章 | **16 个**各自实现（内边距 4 种、圆角 2 种、字号写法不一） | 1 个组件 × 6 色调 × 2 变体 |
| 内容层材质 | **35 处**液态玻璃叠液态玻璃 | 标准材质（`Surface`） |

这些数字单看每一项都「合理」，叠在一起就是「看起来不统一」——眼睛读不出
12% 与 14% 的差别，只觉得哪里不一致。所以这份体系的核心不是「定了几个值」，
而是**把值收敛到有语义的档位，并用测试钉住**。

---

## 2. 分层：两层材质模型

Apple 的 `materials.md` 把界面分成两层，这个划分决定了用什么材质：

| 层 | 内容 | 材质 | 实现 |
|---|---|---|---|
| **内容层** | 卡片、列表容器、表单、统计格 | 标准材质：不透明底 + 发丝描边 + 极轻投影 | `Surface` |
| **功能层** | 侧边栏、底部 Tab Bar、弹窗、底部 Sheet、浮层操作条 | Liquid Glass | `LiquidGlass` |

> `materials.md` 原话：**Don't use Liquid Glass in the content layer.** …
> Instead, use standard materials for elements in the content layer.

玻璃压在玻璃上会让所有卡片落在同一层材质上，层级只能靠间距硬撑——这正是
「看起来不统一」的结构性根源。收敛后 `LiquidGlass` 只剩 **7 处**，全在功能层：

```
lib/ui/adaptive_shell.dart                                        桌面侧边栏 / 侧边栏状态条 / 底部 Tab Bar / 「更多」Sheet
lib/features/words/widgets/word_filter_sheet.dart                 筛选底部 Sheet
lib/features/initialize/configurator/initialization_configurator.dart  初始化配置对话框
lib/features/initialize/widgets/queue_bulk_bar.dart               批量操作浮条
```

守卫：`test/architecture/design_tokens_test.dart › 材质 › LiquidGlass 只能出现在功能层`
（文件白名单，绝对规则）。

### 一个被测试抓到的真实缺陷

`Surface` 一开始是 `DecoratedBox`——底色、描边、投影都对，渲染也正常，但
`ListTile` 与 `InkWell` 把背景与涟漪画在**最近的 `Material` 祖先**上，中间夹
一层带底色的 `DecoratedBox` 会把涟漪整个盖住；`ListTile` 在 debug 下直接抛
断言（`_findIntermediateWidget` 沿祖先链找 `Material`，途中撞见不透明底色就
报错）。现在 `Surface` 自己就是 `Material`：`shape` 承载描边、`elevation`
承载投影、`clipBehavior: antiAlias` 裁涟漪。

守卫：`test/ui/surface_test.dart`（把不透明 `DecoratedBox` 注回去后确实失败）。

---

## 3. Token 层

全部在 `lib/ui/theme/`，每个文件一族。

| 文件 | 导出 | 档位 |
|---|---|---|
| `lexi_colors.dart` | `LexiColors`、`LexiRadius` | 语义色（明暗两套）+ 7 档圆角 + `pill` |
| `lexi_type.dart` | `LexiType` | 9 档字号，每档带行高 |
| `lexi_space.dart` | `LexiSpace` | 12 档间距（2pt 节奏） |
| `lexi_tint.dart` | `LexiTint` | 6 档淡色透明度 + `none` |
| `lexi_motion.dart` | `LexiMotion` | 反馈时长 + 「减弱动态效果」折算 |

### 3.1 字号（`LexiType`）

```
caption 11/14 w500   footnote 12/16   body 13/18   callout 15/20 w500
title   17/22 w600   title2   22/28 w700
page    26/32 w700   display  30/36 w700   hero 34/40 w700
```

最小档 11：macOS 的字号下限是 10，留一档余量。**每一档都必须有行高**——
没有行高的多行文本会挤在一起。

Material 的 `TextTheme` 15 个槽位也全部映射到这九档（`lexi_theme.dart`）。
不映射的话，每个槽位会退回 Material 自带尺寸（labelSmall 11 / labelMedium 12 /
bodySmall 12 / labelLarge 14 / titleSmall 14 / titleMedium 16 / titleLarge 22 /
headlineSmall 24…），而全应用有 75 处在用 `Theme.of(context).textTheme.X`——
「只有 9 种字号」在主题层就被推翻了，而 `fontSize` 守卫看不见它们。

守卫：`test/architecture/design_tokens_test.dart › 字号`、
`test/ui/theme_text_test.dart`。

### 3.2 颜色（`LexiColors`）

明暗两套，`ThemeExtension` 注入，随 `Theme.of(context)` 自动切换。

**四级文字层级**按「对比度单调递减」取值，且每一级都 ≥4.5:1。收敛前
`tertiaryLabel`(#AEAEB2) 只有 1.98:1，比 `quaternaryLabel`(#8E8E93, 2.92:1)
**更弱**——层级是反的，而且两级都读不清（它们被用在禁用按钮、提示与
`labelSmall` 上，那些都是要读的文字）。深色下同样倒挂。

**信号色分成两组**：`accent`/`danger`/`success`/`warning`/`purple` 是**填充**
用色（圆点、进度条、按钮底），`accentText`/`dangerText`/`successText`/
`warningText`/`purpleText` 是**文字**用色。饱和色当文字压在自家 12% 淡底上只有
2–3:1（`success` 最差，1.99:1），读不清。深色模式下两组同值（黑底上饱和色本身
就 ≥4.6:1）。

`card`（白 / `#1C1C1E`）是内容层表面的不透明底——原先 `Surface` 把这个值写死
在组件里。

守卫：`test/architecture/design_tokens_test.dart › 对比度`，对比度是**逐对算出来
的**，不是估的。

### 3.3 圆角（`LexiRadius`）

```
xxs 4   xs 6   sm 10   md 14   lg 18   xl 22   xxl 28   pill 999
```

`xxs` 只给边长 12–16 的微型元素（热力图方块、行内 diff 标签）。高度 ≤10 的
进度条与小圆点一律用 `pill`——Flutter 会把圆角夹到半高，不必按尺寸计算。

### 3.4 间距（`LexiSpace`）

```
s2 2  s4 4  s6 6  s8 8  s10 10  s12 12  s14 14  s16 16  s20 20  s24 24  s32 32  s40 40
```

档位取 2pt 节奏上**真正被反复使用**的值：10 与 14 各被用了近百次，属于实际
主力档位，因此收编为 `s10`/`s14`，而不是硬掰到 8 或 12；反过来 18 只有 8 处、
明显是漂移，就并到 `s20`。

**间距之外的尺寸不属于这套音阶**：表格列宽、点击热区、游戏槽位高度就地命名成
有语义的 `const`（`_rowNumberColumnWidth = 44`、`_speakButtonSize = 92`、
`_moleSlotHeight = 54`…），而不是塞进 `LexiSpace`。

### 3.5 淡色透明度（`LexiTint`）

```
none 0   group 0.04   subtle 0.06   tint 0.12   border 0.30   half 0.50   strong 0.85
```

只保留**意图不同**的那几级。收敛前 `0.06 / 0.07 / 0.08` 三档同时存在、
`0.10 / 0.12 / 0.14 / 0.15 / 0.16` 五档同时存在、描边散在 `0.2 / 0.25 / 0.3 /
0.35`——肉眼读不出差别，只觉得不一致。

### 3.6 动效（`LexiMotion`）

`MediaQuery.disableAnimationsOf` 是系统给应用的唯一「减弱动态效果」信号
（macOS「辅助功能 › 显示器 › 减少动态效果」）。收敛前全仓 **0 处**使用。
`LexiMotion.of(context, duration)` 在开启时折成 `Duration.zero`——隐式动画
组件收到零时长会直接落到终态，调用方不需要写分支。

---

## 4. 组件

| 组件 | 位置 | 说明 |
|---|---|---|
| `Surface` | `lib/ui/widgets/surface.dart` | 内容层表面。`card`（不透明 + 发丝描边 + 投影）/ `inset`（`fill` 淡底、无描边）/ `plain`（纯分组） |
| `LexiBadge` | `lib/ui/widgets/badge.dart` | 徽章。6 色调 × 2 变体（`tint` / `outline`），内边距/圆角/字号/字重固定 |
| `LiquidGlass` | `lib/ui/glass.dart` | 功能层玻璃。**不要用在内容层** |
| `AmbientBackground` | `lib/ui/glass.dart` | 页面底的环境光斑 |

`MasteryBadge` / `InitializationBadge` / `ArticleBadge` / `DetailChip` /
`_CardTag` 等只负责「状态 → 文案 + 色调」的映射，长相一律交给 `LexiBadge`。

### 4.1 徽章为什么要合成不透明底色

徽章底色是 `Color.alphaBlend(tone.withValues(alpha: LexiTint.tint), base)`，
而不是直接把半透明色交给 `Container`：

* 浅色模式 `base = card`（白），徽章与卡片融为一体；
* 深色模式 `base = surface`（纯黑），底色**比卡片更深**。

原因是深色模式的对比度：深色下 `accentText` 就是 `accent` 本身（#0A84FF），
它压在卡片底 #1C1C1E 上只有 4.6:1，已经贴着下限；再把 12% 同色淡底叠在卡片
上，底被提亮，就掉到 **4.09:1**（danger 4.40、purple 4.19）——徽章在深色下
读不清。合成到页面底后六种色调全部回到 5.2:1 以上。

守卫：`test/ui/badge_test.dart` 从**渲染树**里取 `BoxDecoration.color` 与
`Text.style.color` 逐对验，而不是在守卫里重抄一遍公式（抄公式会和组件一起
漂移）。

### 4.2 学习页的进度环

学习页顶部是 44×44 的进度环：环内是**已完成数**、弧长表达比例、旁边两行说
「12 / 45」与「还剩 33 词」。直径取 `studyMinTapTarget`，与旁边的「跳过 /
结束」按钮同高。弧从 12 点顺时针生长，200ms 隐式动画，时长走 `LexiMotion.of`。

环 + 文案与「计数 + 动作」放在 `Wrap` 里：360 宽下自然折成两行，宽屏上并成
一行、左右分列。

---

## 5. 无障碍

| 项 | 做法 |
|---|---|
| 对比度 | 文字与背景逐对 ≥4.5:1；大号/加粗 ≥3:1（WCAG 2.x AA） |
| 不靠颜色单独表意 | 计数胶囊是「中性底 + 彩色圆点 + 常规文字色」，且带 `Semantics`；状态徽章的颜色只是辅助，文案本身说明状态 |
| 增强对比度 | `MediaQuery.highContrastOf` 把 `Surface` 的发丝描边从 `borderSubtle` 加重到 `borderStrong` |
| 减弱动态效果 | `LexiMotion.of`（见 3.6） |
| 纯图标控件 | 必须自带 `Tooltip` / `Semantics` 标签；守卫会拦 |
| 键盘焦点 | `ThemeData.focusColor` 给 accent 淡底；桌面端用户大量用键盘 |
| 触控热区 | `studyMinTapTarget = 44`，顶部小动作、字母块、朗读键都按它取值 |

守卫：`test/ui/accessibility_test.dart`。

---

## 6. 自适应

断点是 `sidebarBreakpoint`（1024 逻辑像素，与旧版 Tailwind 的 `lg:` 一致）：
宽屏走侧边栏，窄屏走底部 Tab Bar（超出 4 个的目的地收进「更多」）。

沉浸式页面（学习、游戏、配对、音标）**只隐藏窄屏的底部 Tab Bar**，桌面侧边栏
从不隐藏——与旧版 `components/app-shell.tsx` 的 `isStudyScreen` 一致。

守卫：`test/app/page_smoke_test.dart` 把 12 条路由 × 4 档宽度（360 / 700 /
1000 / 1440）逐个渲染，断言无异常。布局溢出在测试里是构建期异常，会被
`takeException()` 抓住。断点两侧都覆盖，否则「过断点时布局重排」测不到。

这套矩阵抓到过一个真实缺陷：`/import` 在 360 宽下
`RenderFlex overflowed by 11 pixels on the right`——步骤标题行里标题没有宽度
约束，按自然宽度撑破整行。改成 `Expanded` 让标题换行。

---

## 7. 守卫清单

样式是唯一没有编译器保护的东西，所以每一条约定都配一条测试。

| 文件 | 守什么 |
|---|---|
| `test/architecture/architecture_test.dart` | 分层边界、函数 ≤40 行、`build()` ≤80 行、构造函数参数 ≤5、无空 catch、不用字符串判错误类型、`lib/domain`+`lib/services` 无裸数字、时间常量自洽、`dart:io` 只在 `*_native.dart` |
| `test/architecture/design_tokens_test.dart` | 无 `fontSize`（token 文件除外）、无 `circular` 数字字面量、间距落在 `LexiSpace`、无 `withValues(alpha: 数字)`、`LiquidGlass` 只在功能层、音阶严格递增、四级标签对比度单调递减且 ≥4.5:1、信号文字色 ≥4.5:1、主按钮白字 ≥3:1 |
| `test/ui/surface_test.dart` | `Surface` 自己承载涟漪；三种形态的底色/描边/抬升；增强对比度加重描边 |
| `test/ui/badge_test.dart` | 六色调 × 明暗两套的对比度；六色调几何完全一致；`outline` 只多一条描边 |
| `test/ui/theme_text_test.dart` | 15 个 `TextTheme` 槽位的字号都在 `LexiType` 里、都带颜色与行高；`focusColor`/`hoverColor` 非空 |
| `test/ui/accessibility_test.dart` | 纯图标控件有标签；`LexiMotion.of` 的两种行为 |
| `test/features/study/progress_ring_test.dart` | 环的直径/弧长/文案；六档宽度不溢出 |
| `test/app/page_smoke_test.dart` | 12 路由 × 4 宽度的构建期异常；导航形态随断点切换 |

### 反向验证

每一条新守卫都必须**先证明它会失败**，否则「守卫全绿」不说明任何事。本次
新增的守卫都做过反向验证，例如：

* 把不透明 `DecoratedBox` 注回 `Surface` → `ListTile` 断言失败；
* 把徽章底色改回压在卡片底 → 「深色 · accent」以 4.08:1 失败；
* 把 `labelSmall` 换回裸 `TextStyle` → 4 条主题用例失败；
* 注入裸图标 `InkWell` → 无障碍守卫以准确行号失败；
* 把进度环的弧长写死成整圈 → 像素计数用例以 `Expected: a value greater than <407>` 失败。

---

## 8. 刻意偏离旧版 CSS 的三处

1. **材质分层**：旧版内容层与功能层都用玻璃（`.liquid-glass` /
   `.liquid-glass-elevated` / `.liquid-glass-subtle` / `.liquid-glass-edge` /
   `.liquid-glass-specular` / `.liquid-glass-interactive`）；本版内容层改标准
   材质（见第 2 节）。
2. **九档字号**：旧版字号散在 Tailwind 的 `text-xs`…`text-2xl` 加 **24 种
   行内任意值**（`text-[9px]`…`text-[30px]`，含 `10.5px` / `11.5px` / `12.5px` /
   `13.5px` / `14.5px` / `15.5px` / `16.5px` 七个半点值，共 **254 处**）；
   Flutter 侧在收敛前也是 24 种（399 处）——说明这不是某一端的疏忽，而是
   「随手写一个刚好合适的值」这件事本身的必然结果。本版收成九档并强制带行高。
3. **信号色分填充与文字两组**：旧版同一个色值既做底也做文字；本版拆成
   `accent` 与 `accentText` 等两组，保证文字始终 ≥4.5:1。

用户已明确允许这些偏离（「不对齐也没事」），此处记录以免日后被当成缺口。
