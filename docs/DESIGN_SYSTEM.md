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

### 3.7 版面（`LexiLayout`）

字号、圆角、间距、透明度都收敛之后，还剩一族值没有归属：**版面宽度**。
它不落在任何间距音阶里，因为它的含义不是「两个元素之间多远」，而是
「内容允许长到多宽」。

| 档位 | 值 | 用在哪 |
|---|---|---|
| `pageMaxWidth` | 1040 | 普通页的正文列（今日 / 单词本 / 词条详情 / 统计 / 设置 / 初始化 / 添加） |
| `immersiveMaxWidth` | 840 | 沉浸页与单列向导（学习 / 游戏 / 配对 / 音标 / 文章） |
| `readingMaxWidth` | 720 | 长文本段落（释义、例句、笔记） |
| `wideBreakpoint` | 900 | 双栏布局阈值（与侧边栏断点 1024 是两件事） |
| `cardGap` / `sectionGap` | 16 / 32 | 同级卡片之间 / 分区之间 |
| `minTapTarget` | 44 | 触控热区下限（原 `studyMinTapTarget`，提升为全局） |
| `labelColumnWidth` | 88 | 键值对里的键列（原先 88 / 76 / 118 三套并存） |

`pageMaxWidth` 取 1040 不是拍的：默认窗口 1280 减去 256 侧边栏与 40 栏距
后可用 984，**小于 1040**，因此默认窗口下的渲染结果与限宽前完全一致，
只有宽于约 1336 的窗口才开始出现居中留白。这样改版面不会带来
「一打开就变窄」的回归。

限宽有两处实现，共用同一个 `contentCapKey` 供守卫测量：

* `AdaptiveShell._buildWide`：外壳内容区（覆盖全部 8 条分支路由）；
* `ContentWidthCap`（`lib/ui/widgets/page_shell.dart`）：包装**不在外壳里**
  的顶层路由（`/import`、`/article`、`/games`、`/match`）。包装写在
  `app/router.dart` 的一张表里，因为「哪几页是顶层路由」只有那张表说得清——
  漏掉一页就是那一页在宽窗口下被拉长。

守卫：`test/app/page_width_test.dart` 对 12 条路由在 1440 宽下量**渲染宽度**，
断言「≤ 上限」「顶到上限」「左右留白相等」，并断言断点以下不出现限宽节点。

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

### 4.3 页面外壳（`PageShell`）

**为什么必须有它**：收敛前「页头 + 滚动区 + 底部动作」这三件事各页自己写，
于是同一件事出现了多种写法：

| 事实 | 收敛前 |
|---|---|
| 根容器 | 9 个页面写 `Scaffold`，3 个（统计 / 添加 / 初始化）完全不写 |
| 页头 | `AppBar` 只有 2 处，其余全是各页手写的 `Column + Text` |
| 左右内边距 | 20 / 16 / 32 / 96 四种取值 |
| 正文宽度上限 | 全仓只有 `game_shell.dart` 一处（760） |

`PageShell` 只做三件事，并强制它们对全部页面同构：限宽居中、提供
`Scaffold` 宿主、吸底动作区（滚动区自动补底部内边距）。

**它必须是真的 `Scaffold`，不能只给一个 `Material`**：这一点是迁移时被
测试抓出来的——`ScaffoldMessenger.showSnackBar` 要求「当前有后代 Scaffold」，
只有 Material 时它在 debug 下直接断言失败（`_scaffolds.isNotEmpty`），
词条详情页的「已排入补全队列」这类提示会全部消失。`Material` 能解决
「找不到 Material 祖先」，但解决不了「提示没地方挂」。

**它不负责背景**：环境光斑由两处统一绘制——导航外壳（8 条分支路由）
与 `app/router.dart` 的 `_capped`（4 条顶层路由）。页面自己再叠一层
会出现双层光斑，光斑颜色被乘两遍。

### 4.3.1 断点量的是「内容宽度」还是「窗口宽度」

限宽之后，内容区的可用宽度不再等于窗口宽度。这两件事必须分开：

| 断点 | 量的是什么 | 用在哪 |
|---|---|---|
| `sidebarBreakpoint`（1024，`core/constants.dart`） | **窗口**宽度 | 导航形态：侧边栏 / 底部 Tab |
| `LexiLayout.wideBreakpoint`（900） | **内容**宽度 | 页内排布：筛选栏铺开 / 收进面板 |

迁移时踩过一次：词库的筛选栏原本用 `sidebarBreakpoint` 判断「宽屏就平铺
筛选控件」。内容被限宽到 ≤1040 之后，那个条件**永远不成立**，宽屏用户
会一直看到「筛选」按钮——而且不会有任何报错，只是功能悄悄退化。
凡是在 `LayoutBuilder` 里按 `constraints.maxWidth` 分支的地方，
比的都必须是 `LexiLayout.wideBreakpoint`。

### 4.3.2 卡片只有一种（`SectionCard`）

收敛前「带标题的卡片」有五套实现：`SectionCard`（内边距 18）、
`SettingsSectionCard`（14）、`StatCard`（16）、`ArticleSectionCard`（14）、
`ConfiguratorCard`（14）。标题样式完全一样（`LexiType.callout` + w600），
差别只在一两像素的内边距和「有没有副标题 / 右侧内容 / 图标」这些**开关**。

现在差异收成参数：`icon`（标题前语义图标）、`subtitle`（一句「为什么」）、
`trailing`（右侧附加内容）。内边距统一 `LexiSpace.s16`、标题间距
`LexiSpace.s12`——都在间距音阶上，不再是「刚好合适的 18」。
`SettingsSectionCard` 与 `ArticleSectionCard` 退化成薄壳。

### 4.4 页头（`PageHeader`）

一条规则：`title` 一律 `LexiType.page`，`subtitle` 一律一句话说明**本页能
做什么**。收敛前「页面标题」有 4 种字号、3 种对齐、2 种副标题语义
（今日页的副标题是品牌口号，1280 窗口下与侧边栏的 `LexiLoop` 商标相距 40px）。

动作的规则：`PageHeaderAction` 默认渲染**图标 + 文字**——只有图标的按钮
要靠悬停提示才认得出，而 macOS 上「鼠标恰好停在按钮上」没人能保证。
同时最多平铺 2 个动作，其余收进「⋯」菜单：词条详情页曾经把「补全 / 有道
词典 / 编辑 / 重新生成 / 删除」五个文字按钮平铺在标题右侧，删除与重新生成
相隔约 40 像素。把危险动作从一等位置降下来，是布局问题，也是安全问题。

### 4.5 状态三件套（`PageEmptyState` / `PageErrorState`）

规则不是「长得一样」，而是**每个状态都必须给出下一步**。

* `PageErrorState` 有 `secondaryLabel` / `onSecondary`，且 `details` 默认折叠：
  初始化队列曾经把 `HTTP 422 {"error":{…}}` 整段当正文显示在词条行里。
* 沉浸路由（学习 / 游戏 / 配对 / 音标）与顶层路由上的失败态**必须**给第二
  出口：那里没有导航外壳可以依赖。学习页的 `StudyErrorView` 因此把
  `onExit` 设为必填参数——它曾经只有「重试」，失败原因持久时用户只能杀进程。

---

### 4.5.1 图表的可读性

「每日作答」有两条曲线（作答 / 正确），收敛前**没有任何图例**：读者得先
猜哪条是哪条，而同轴对比正是这张图的核心主张。现在图例常驻，并打开了
点击读数——只有两条线时，读者最想知道的正是某个具体日子的数值。

Y 轴不再留「4 小时 13 …」这类截断：数值格允许折两行，长数值（累计时长）
用更宽的格子（168）。一排被截断的数字比不显示更糟：读者会以为数据没算完。

概览的六个格子在「零词条 + 零作答」时全部为 0，对「下一步做什么」零信息量，
因此换成一句引导而不是六个 0。

### 4.5.2 控件不要铺满宽屏

限宽只解决了「整页有多宽」，没解决「一个控件该有多宽」。收敛后仍在
1280 窗口下出现两类拉伸：

| 控件 | 症状 | 现在 |
|---|---|---|
| 筛选/排序下拉框 | `Expanded` + `isExpanded: true` 让箭头落在内容区最右端，离标签约 1000px，控件与它标注的值失去联系 | 不 `Expanded`，用 `Flexible` 贴着标签；两个下拉框并排一行 |
| 设置页滑条 | 铺满 1040，标签在最左、数值在最右（相隔近 1900px），刻度被拉到十几像素一格，读不出精确位置 | 整页收窄到 `LexiLayout.readingMaxWidth`（720），滑条与正文列同宽 |

判断依据是「控件与它的标签/数值是否还读得成一个整体」，不是控件占了多少像素。

补充两条实测出来的：

* **表单页整页收窄**（添加词条 720）：输入框铺到 1040 时，一个只填几个字的
  字段也长得一眼看不完；收窄之后字段标签正好落在输入框上方。
* **主按钮不铺满整行**：首页「开始学习」目标为 0 时是一条 1040 宽、通体
  蓝色、上面四个字的横幅——全页最重的视觉元素落在一个主次不明的横条上。
  按内容取宽、左对齐；只有窄屏（< 480）才铺满，那里拇指更好按。

### 4.5.3 一个图表不要套两层标题

「复习趋势」（卡片外的标题 + 档位切换）叠在「每日作答」（卡片标题）之上，
说的是同一件事，而档位只作用于这张图。现在标题与档位都归卡片自己。

同理，空态**不要留固定高度的空框**：折线图的高度是给折线用的，没有数据时
一张 200 高的空卡片只会让「这段时间还没有复习记录」飘在顶部。

同理，**列表为空时不要画分页条**：初始化队列曾在「没有符合条件的任务」
上方画一行「第 1 / 1 页 · 共 0 个词条」，读起来像分页坏了。

指标格的底色也在这个范畴：`fill` 本身是中灰，半透明叠在白卡上仍是结实的
一块灰，四个指标格看起来像四个「未加载」的占位块。分组底用 `LexiTint.group`
（4%），只够分组，不抢读数。

### 4.5.4 顶层路由必须有「离开」的入口

`/import`、`/article`、`/games`、`/match` 不套导航外壳：没有侧边栏、没有底部
Tab、也没有 AppBar。它们的「离开」只能由页面自己给。收敛过程中发现三处死胡同：

| 页面 | 收敛前 | 现在 |
|---|---|---|
| `/import` | 唯一出口是「三步都走完后的结果卡」，选错文件就出不去 | 页头返回（`importBack`） |
| `/match` 准备页 | `exit()` 只是把状态退回准备态，也就是用户已经站着的地方 | 页头返回 → `/games` |
| `/phonetics` 准备页 | 同上 | 页头返回 → `/games` |

**`context.canPop()` 在导航外壳的分支目的地里不可靠**：`StatefulShellRoute`
的分支导航器里 `canPop()` 返回 `true`，但 `pop()` 弹掉的是与当前页相同的那个
条目——位置不变、界面不动，按钮看起来坏了。所以 `backButton` 有 `preferPop`
参数：栈内页面（词条详情）用它默认的「能出栈就出栈」，分支目的地必须传
`preferPop: false`，直接 `go` 到兜底位置。

守卫：`test/features/games/setup_back_exit_test.dart`（断言点击后路由真的变成
`/games`，而不是「按钮存在」）；`test/features/import/import_page_test.dart`。

### 4.5.5 配置器：预设优先、细节折叠

配置器打开时有六块内容（预设 / 作用范围 / 字段 / 数据源 / 预览 / 摘要），
除预设外全部默认展开：16 个字段和 6 个数据源与预设平铺在同一屏，
第一印象是「这个对话框好复杂」，而绝大多数情况下用户只需要
「选个方案 → 创建任务」。

现在预设之后的**三项细节默认收起**（`ConfiguratorDisclosure`），收起时保留
一行当前状态摘要（「全部词条」「1 个字段」「3 个来源 · 按顺序尝试」）——
折叠不等于隐藏，不展开也能确认自己选了什么。

预设卡从固定宽的 `Wrap` 改为**按可用宽度算列数**：4 张卡在左栏只放得下 3 张，
第 4 张单独换行、右边空出三分之二，看起来像布局坏了。2×2 或 1×4 都整齐，3+1 不整齐。

守卫：`test/features/initialize/configurator_test.dart` 的「细节默认收起」用例
断言收起时字段网格**没有被构建**（`find.text('例句') findsNothing`），
展开后才出现——只断言「摘要行还在」是不够的，那条断言在展开时同样成立。

### 4.6 动作与确认分级

危险动作的确认强度必须按**后果**排，不能按「名字听起来危不危险」排。
收敛前同一类动作的谨慎度彼此矛盾：

| 动作 | 收敛前 | 现在 |
|---|---|---|
| 导出备份（可再生） | 要求打 `EXPORT` | 不变 |
| 清空全部数据 | 要求打 `DELETE` | 不变 |
| **导入 JSON 备份（12 表全量替换）** | **两个入口两套门槛**：设置页打 `IMPORT`，词库页零确认 | 两个入口共用 `confirmBackupImport`，都要打 `IMPORT` |
| 撤销导入批次 | 确认框不写文件名与时间 | 待办（S3） |
| 「重置学习进度」（CSV 导入） | 提交时弹确认 | 不变 |
| 「重置学习进度」（文章导入） | **勾选即生效** | 与 CSV 同一条确认 |
| 手动批量「全部确认加入」 | **零确认写库** | 确认框含行数，并说明无撤销 |
| 队列「批量重试」 | **零确认** | 确认框含词条数，并说明会再打词典/AI |

三个工具函数承担这套规则：

* `confirmAction(context, title:, body:, confirmLabel:, destructive:)` —
  普通点击确认（`lib/ui/feedback/confirm_dialog.dart`）；
  `body` 必须说清**做什么 / 作用范围 / 能不能撤销**；
* `TypedConfirmDialog` — 打字确认，用于不可逆且作用域大的动作；
* `runGuarded` / `runQuietly` — 执行 + 归一化错误 + 界面反馈，返回 `bool`
  让调用方回滚乐观更新。

**失败必须可见**：`saveSettings` 是设置页唯一的写入口，它在失败时
（1）让 `appSettingsProvider` 失效、界面回到库里真实的值，
（2）通过 `appMessengerKey` 弹一条提示——这条路径此前被
`unawaited(saveSettings(...))` 静默吞掉，用户只会觉得「设置不生效」。

守卫：`test/features/settings/save_failure_test.dart`（写失败必有提示、
异常不逃逸）；`test/features/games/result_and_retry_test.dart`；
`test/features/settings/data_management_section_test.dart`（导入备份必须打 `IMPORT`）。

---

### 4.7 怎么在没有窗口的环境里看到页面

macOS 上 `screencapture` 与 AppleScript 的窗口查询都需要「录屏 / 辅助功能」
授权；未授权时截图全黑、`count of windows` 恒为 0（连 `Terminal` 也是 0，
所以那不是应用的问题）。在拿到授权之前，用离屏渲染：

```
flutter test --no-pub test/tools/screenshot_tool.dart   # → build/screens/*.png
```

它把渲染树直接画进 PNG，绕开窗口服务。两个必要条件写在文件头：
**装一份带中文的真字体**（否则文字是方块）、**装 `MaterialIcons`**
（否则图标是方块）。`lucide_icons_flutter` 用的是另一套字体，未装时导航
图标仍会是方块——这只影响截图，不影响真机。

### 4.7.1 高宽两个维度都要测

自适应用例此前只覆盖宽度（360 / 700 / 1000 / 1440）与一个固定的 900 高。
**高度比宽度更容易被漏掉，而溢出恰恰在那里发生**：固定高度的卡片、吸底条、
页头叠在一起，840 高时宽宽松松，560 高时就把内容挤成负空间。

补上最小窗口（`main.dart` 限制的 560 高）之后立刻抓到一处：单词本的空态卡
（图标 + 标题 + 说明 + 三个按钮）在 360×560 下超出 196 像素。修法不是压缩
间距，而是让它**可滚动**——空间够时看起来仍是静态一屏，不够时能滚到按钮。

矩阵规模：12 条路由 × 4 档宽度（常规高度）+ 12 × 2 档最小窗口 = 72 条。
宽度与高度基本正交，不做 12 × 4 × 2 的全交叉。

### 4.7.2 窄屏页头只平铺一个动作

`PageHeader` 在 <480 宽时只平铺**一个**动作，其余进「⋯」：360 宽下平铺两个
动作 + 一个 trailing 会把页头摞成三行（标题一行、按钮两行），页头本身吃掉
三分之一屏。平铺一个主按钮 + 一个「⋯」让页头回到两行，主线动作也没丢。

同一条思路用在「当前词条掌握程度」条上：360 宽时「图标 + 文字 + 详细统计」
三样挤一行会把文字压成三行；窄屏改为去掉图标块、把链接挪到下一行，
卡片高度回到正常。

截图工具现在每个页面出**桌面 + 手机**两张（`build/screens/<page>_phone.png`）：
两端的布局分支完全不同（侧边栏/底部 Tab、平铺筛选/筛选面板、单行/两行页头），
只截桌面等于只验证了一半。

### 4.8 为什么设置页仍然是 7 个 tab 一排

原方案里有「7 个 tab 收成两组」。实际看过之后**没有做**，理由记在这里以免
被当成遗漏：

* 7 个标签在 `readingMaxWidth`(720) 里一行放得下，不折行、不需要横向滚动；
* 顺序本来就是分组的——`学习计划 / 题型 / 播放` 是学习行为，`数据源 /
  词汇与考试 / AI 模型 / 数据管理` 是数据与模型配置。缺的只是一条分组线，
  而不是分组本身；
* 「先选组再选 tab」会**多一次点击**，还会把 `数据管理`（清空数据、导入备份
  所在，一个需要被看见的地方）藏到一层后面。对 7 个条目来说，这个代价
  大于收益。

如果将来 tab 继续增加（>9），再考虑二级结构；判断依据是「一行放不放得下」，
不是「数字看起来大」。

## 5. 无障碍

| 项 | 做法 |
|---|---|
| 对比度 | 文字与背景逐对 ≥4.5:1；大号/加粗 ≥3:1（WCAG 2.x AA） |
| 不靠颜色单独表意 | 计数胶囊是「中性底 + 彩色圆点 + 常规文字色」，且带 `Semantics`；状态徽章的颜色只是辅助，文案本身说明状态 |
| 增强对比度 | `MediaQuery.highContrastOf` 把 `Surface` 的发丝描边从 `borderSubtle` 加重到 `borderStrong` |
| 减弱动态效果 | `LexiMotion.of`（见 3.6） |
| 纯图标控件 | 必须自带 `Tooltip` / `Semantics` 标签；守卫会拦 |
| 键盘焦点 | `ThemeData.focusColor` 给 accent 淡底；桌面端用户大量用键盘 |
| 触控热区 | `LexiLayout.minTapTarget = 44`（原 `studyMinTapTarget` 提升为全局），顶部小动作、字母块、朗读键都按它取值 |

守卫：`test/ui/accessibility_test.dart`。

---

## 6. 自适应

断点是 `sidebarBreakpoint`（1024 逻辑像素，与旧版 Tailwind 的 `lg:` 一致）：
宽屏走侧边栏，窄屏走底部 Tab Bar（超出 4 个的目的地收进「更多」）。

沉浸式页面（学习、游戏、配对、音标）**只隐藏窄屏的底部 Tab Bar**，桌面侧边栏
从不隐藏——与旧版 `components/app-shell.tsx` 的 `isStudyScreen` 一致。

### 6.1 导航分组

8 个目的地平铺时，侧边栏读起来是 8 条等权重的行：「音标」与「设置」一样大，
「初始化」夹在「添加」与「统计」之间。用户找不到主线，是因为界面没给出主线。

`AppDestination.group` 把它们分成四组，分组**只改变呈现**，不改路由、
不改 `⌘1`–`⌘8` 的顺序、不改 `mobilePrimaryPaths`——深链接、书签与测试都不受影响：

| 分组 | 侧边栏呈现 | 成员 |
|---|---|---|
| `primary` | 无组头 | 今日 / 复习 / 单词本 |
| `library` | 组头「词库准备」 | 添加 / 初始化 |
| `training` | 组头「训练」 | 音标 |
| `reference` | 组头「查阅」 | 统计 / 设置 |

「更多」底部 Sheet 也按同一顺序排列：同一个应用里「添加」在两处的邻居应当一致。

**为什么不把「查阅」钉在侧边栏底部**：钉底少一次滚动，但窗口最小高度 560、
系统字体放大时，钉死的那一组会先把上方的 `Expanded` 挤到 0 再溢出。
分组标题已经能表达「这几项不是主线」，可滚动的列表在任何字号下都不会溢出。

### 6.2 正文列限宽

见 3.7。要点：限宽在**外壳内容区**与**顶层路由包装**两处，共用
`contentCapKey`；1440 宽窗口下正文列 1040（沉浸页与单列向导 840），
默认 1280 窗口下不受影响。

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
| `test/app/page_width_test.dart` | 12 路由在 1440 宽下正文列 ≤ 版心上限、顶到上限、左右留白相等；断点以下不出现限宽节点 |
| `test/features/games/result_and_retry_test.dart` | 结算页「再来一局」走 `restart()` 而不是只对准备态有效的 `start()`；结算失败有「继续本轮」；音标错答后存在一个真的能把状态推回可作答的动作 |
| `test/features/settings/save_failure_test.dart` | 设置写库失败必有可见提示，且异常不再抛给调用方（否则会被 `unawaited` 吞掉） |
| `test/data/import/csv_parser_test.dart` | 导入时 HTML 实体被还原；`&amp;lt;` 只解一层（单遍替换）；不含实体的文本原样保留 |
| `test/features/import/import_page_test.dart` | 顶层路由的导入页有返回入口（此前是死胡同）；导入备份必须打 `IMPORT` |
| `test/features/words/words_page_test.dart` | 被筛空时空态必须留一个「清除全部筛选与搜索」的按钮，且点了真的回到全部词条 |
| `test/features/words/import_backup_gate_test.dart` | 词库页的「导入备份」在确认前一次都不调用导入服务；只有打了 `IMPORT` 才真的执行 |
| `test/features/games/setup_back_exit_test.dart` | 配对/音标的准备页有返回入口，且点击后路由**真的**变成 `/games`（`canPop()` 在分支里会假阳性） |
| `test/features/dashboard/reminder_deep_link_test.dart` | 提醒卡的「查看错词 / 查看到期」真的把 `wordQueryProvider` 设成对应筛选并落到单词本，而不是只跳过去 |
| `test/app/page_smoke_test.dart` | 12 条路由 × 4 档宽度 + 2 档最小窗口高度都不抛异常（原来是 4 档宽度 × 一个 900 高） |

### 反向验证

每一条新守卫都必须**先证明它会失败**，否则「守卫全绿」不说明任何事。本次
新增的守卫都做过反向验证，例如：

* 把不透明 `DecoratedBox` 注回 `Surface` → `ListTile` 断言失败；
* 把徽章底色改回压在卡片底 → 「深色 · accent」以 4.08:1 失败；
* 把 `labelSmall` 换回裸 `TextStyle` → 4 条主题用例失败；
* 注入裸图标 `InkWell` → 无障碍守卫以准确行号失败；
* 把进度环的弧长写死成整圈 → 像素计数用例以 `Expected: a value greater than <407>` 失败；
* 去掉 `AdaptiveShell._buildWide` 的限宽 → `/statistics` 以
  `Expected: a value less than or equal to <1040.5> / Actual: <1184.0>` 失败；
* 把配对结算页的 `onReplay` 改回 `start` → 「走 restart()」用例失败；
* 去掉音标错答的「再试一次」按钮 → 「仍存在可作答动作」用例失败；
* 把 `saveSettings` 的失败提示去掉 → 「写库失败时界面出现提示」用例失败；
* 让 `decodeHtmlEntities` 退回链式 `replaceAll` → 「`&amp;lt;` 只解一层」用例失败；
* 把 `PageShell` 的 `Scaffold` 换回裸 `Material` → 词条详情的
  「已排入补全队列」提示不再出现（`_scaffolds.isNotEmpty` 断言）；
* 把筛选栏的断点改回 `sidebarBreakpoint` → 宽屏下筛选控件不再平铺
  （静默退化，只有截图或点开面板才看得出来）；
* 去掉词库页「导入备份」前的 `confirmBackupImport` → 守卫用例失败；
* 去掉准备页的 `leading: backButton(...)` → 「点了回到训练页」用例失败；
* 把配置器三项细节改成默认展开 → 「细节默认收起」用例失败（**这条最初写歪了**：
  只断言摘要行存在，展开时同样成立，于是守卫形同虚设；改成断言收起时字段网格
  未被构建才真正拦住）；
* 把 `_capped` 里的 `ContentWidthCap` 去掉 → 12 条路由的限宽用例失败；
* 把「再来一局」接回 `start()` → 「结算态只认 `restart()`」用例失败；
* 把空态的「清除全部筛选与搜索」按钮删掉 → 对应用例失败；
* 把 `decodeHtmlEntities` 退回链式 `replaceAll` → 「`&amp;lt;` 只解一层」用例失败；
* 去掉提醒卡的 `setWrongOnly` → 「查看错词」用例失败（筛选没落地）；
* 把空态卡改回 `Align + Padding`（不可滚动）→ 360×560 的最小窗口用例失败。

**反向验证的纪律**：不是「加一个测试就算有守卫」。每新增一条守卫，都要把实现
改坏、确认它真的红，再改回来。上面「配置器」那条就是反例——第一版断言在
两种实现下都成立，等于没有守卫。

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
