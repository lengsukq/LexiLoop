# 主题与外观系统

> 2026-10-18 起，LexiLoop 的主色与次色由用户选择；本文说明「选什么、存在哪、
> 怎么推导、为什么不会读不清」。设计 token 的其余部分见
> [设计系统](DESIGN_SYSTEM.md)。

## 1. 用户能改什么

设置 › 外观：

| 项 | 取值 | 默认 |
|---|---|---|
| 外观模式 | 跟随系统 / 浅色 / 深色 | 跟随系统 |
| 主色 | 12 个预设 + 自定义色相/饱和度 | 薄荷 `#35C989` |
| 次色 | 同一套预设 + 自定义 | 靛蓝 `#5E5CE6` |

- 主色：主动作（填充按钮）、链接、进度、选中态、键盘焦点、环境光左上的光斑。
- 次色：次级动作（描边按钮）、双色渐变、图表第二序列、环境光右下光斑、
  分区色的轻微染色。
- 危险（红）、成功（绿）、警告（橙）、关联紫（`purple`）**不随主题变化**。
  它们表达的是状态与语义，不是品牌色；让「红色主色」把危险色一起改掉，
  会让用户分不清「这是主题」还是「这是报错」。

所有修改即时写库，没有「保存」按钮。写入失败会回滚到库里的真实值并提示。

## 2. 存储

`settings` 表仍是 key → `value_json` 的键值表，没有 schema 迁移：

| 键 | 类型 | 说明 |
|---|---|---|
| `themeMode` | `"system" \| "light" \| "dark"` | 未知值回 `system` |
| `themePrimaryColor` | `int`（ARGB） | 只接受 0–0xFFFFFFFF，强制不透明 |
| `themeSecondaryColor` | `int`（ARGB） | 同上 |

解析规则集中在 `lib/domain/models/app_settings.dart` 的 `_parseAppearance`：
类型不符、越界、字符串色值一律回默认值。备份导入会带上这三个键，恢复后
`appSettingsProvider` 已在失效清单里，主题会自动更新。

## 3. 「色种」不是最终颜色

用户选的是**色种（seed）**。最终强调色由
`lib/ui/theme/lexi_color_math.dart` 推导：

1. 取 seed 的 HSL；饱和度夹到 55%–85%，色相保留；近灰（饱和度 <5%）用默认
   薄荷色相。
2. 浅色模式 `accent` 亮度 50%，深色模式 66%——12 个预设因此看起来像同一套
   色板，而不是「有的刺眼、有的发灰」。
3. `accentDeep` 在浅色模式再暗 12%（渐变终点/按压态）；深色模式与 `accent`
   同值。
4. `accentText` / `secondaryText`：在页面底、卡片底、`fill` 压卡片、`fill` 压
   页面底四种背景上逐步调亮度，直到全部 ≥4.8:1——比 4.5 多留一点余量，
   因为同样的文字还会落在四种分区底色上。
5. `onAccent` / `onSecondary`：在近黑、白、纯黑里选「最差背景上也最好」的
   那个；近黑不够 4.5:1 时退纯黑。
6. 分区色（`LexiTones`）：保留薄荷/浅蓝/淡紫/杏色四组手调基色，混入 4% 的
   主色或次色；若染色让最弱的四级标签掉到 4.5:1 以下，再把底色往白/黑推
   一步。前景色按「分区底 + 卡片底」重新收敛。
7. 环境背景：主色左上、次色右下的静态径向渐变（浅色 11%/7%，深色 18%/14%），
   不做动画、不做模糊，避免低端 Android 掉帧。

## 4. 预设

| id | 名称 | 色值 |
|---|---|---|
| `mint` | 薄荷 | `#35C989` |
| `blue` | 海蓝 | `#0A84FF` |
| `teal` | 青 | `#30B0C7` |
| `green` | 草绿 | `#34C759` |
| `indigo` | 靛蓝 | `#5E5CE6` |
| `purple` | 紫 | `#AF52DE` |
| `pink` | 粉 | `#FF2D55` |
| `red` | 红 | `#FF3B30` |
| `orange` | 橙 | `#FF9500` |
| `yellow` | 黄 | `#FFCC00` |
| `brown` | 棕 | `#A2845E` |
| `graphite` | 石墨 | `#8E8E93` |

新增预设只需在 `LexiPalette.presets` 里加一条；色值会自动进入
`test/ui/theme_palette_test.dart` 的 12×2 对比度矩阵，不需要另写测试。

## 5. 代码入口

| 文件 | 职责 |
|---|---|
| `lib/domain/models/app_settings.dart` | `AppThemeMode`、`AppearanceSettings`、解析与写回 |
| `lib/ui/theme/lexi_color_math.dart` | HSL 调整、对比度计算、可读性收敛 |
| `lib/ui/theme/lexi_colors.dart` | `LexiColors.resolve`、中性色、圆角、玻璃底色 |
| `lib/ui/theme/lexi_tones.dart` | 四组分区色（`ThemeExtension`） |
| `lib/ui/theme/lexi_appearance.dart` | 设置 → `Color/ThemeMode` 的界面层模型 |
| `lib/ui/theme/theme_providers.dart` | `appearanceProvider`、`themeBundleProvider` |
| `lib/features/settings/appearance_section.dart` | 设置页外观分组 |
| `lib/features/settings/appearance_controls.dart` | 模式选择、色板、自定义对话框、预览 |

`main()` 在 `runApp` 前最多等 250ms 预读外观，避免深色用户看到白屏首帧；
超时或失败不阻断启动，读到设置后会平滑切过去。只使用一个
`ProviderContainer`，不会出现两个数据库实例。

## 6. 验证

- `test/ui/theme_palette_test.dart`：12 预设 × 明暗 × 四种文字背景 + 四种分区，
  以及白/黑/灰/黄四种极端色种；全部 ≥4.5:1。
- `test/architecture/design_tokens_test.dart`：默认色板的四级标签、分区、按钮
  文字对比度；圆角/间距/透明度音阶。
- `test/features/settings/appearance_section_test.dart`：点色板/切模式/自定义/
  恢复默认是否写对键。
- `test/app/theme_apply_test.dart`：设置 → 主题包的接线与坏值兜底。

## 7. 已知取舍

- 弹窗保持不透明：表单与确认框的第一要务是文字可读，背景模糊会降低对比度
  并增加 GPU 开销。磨玻璃只用于导航、Sheet、浮条与配置器。
- 不做滚动折叠大标题：那需要把 `PageShell` 改成 Sliver 结构，风险覆盖全部
  路由；本轮用 hero 卡、环境光与入场动效表达「轻快」。
- 色相/饱和度自定义不暴露亮度：亮度由引擎接管，用户不需要为了「让按钮上的
  白字看得清」自己调深浅。
