# LexiLoop：Next.js 原版 → Flutter 版功能对照表

> 对照基准：`main` 分支的 Next.js 实现（`src/`）。
> 被对照实现：`flutter` 分支（`lib/`）。
> 判定方式：逐条读旧版实现，再在 Flutter 侧找对应实现并用文件证据确认；**不以文档自述为准**。

---

## 1. 结论

| 项 | 结论 |
|---|---|
| 用户可见能力总数（本表逐条列出） | 78 条 |
| 已对齐 | 见 §2–§10 各表 |
| **刻意舍弃**（有明确理由，不算缺口） | 5 条，见 §11 |
| **已知差异**（能做但选择不做 / 形态不同） | 见 §12 |

判定标准是「旧版用户能做的事，Flutter 版也能做」；内部实现形态（服务端 → 本地、PostgreSQL → SQLite、API 路由 → 服务调用）不计入差异。

---

## 2. 外壳与全局

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 8 个主导航（今日/复习/单词本/音标/添加/初始化/统计/设置） | `components/app-shell.tsx`、`app/(main)/layout.tsx` | 已对齐 | `lib/ui/adaptive_shell.dart`、`lib/ui/navigation/destinations.dart`、`lib/ui/navigation/route_paths.dart` |
| 桌面侧边栏 / 移动底部 Tab 自适应（≥1024 断点） | 同上 | 已对齐 | `lib/ui/adaptive_shell.dart` |
| 键盘快捷键 ⌘1–⌘8 切页 | `app-shell.tsx` | 已对齐 | `lib/app.dart` |
| 液态玻璃视觉系统 | `app/styles/glass.css` | 已对齐 | `lib/ui/glass.dart`、`lib/ui/theme/**` |
| Toast 提示 | `components/toast.tsx` | 已对齐（形态不同） | `ScaffoldMessenger` / `SnackBar` |
| 状态徽标（掌握度 / 初始化状态） | `components/status-badges.tsx` | 已对齐 | `lib/ui/widgets/status_badges.dart` |
| 后台任务驱动（启动回收 + 周期推进） | `components/background-keepalive.tsx`、`api/background/{tick,keepalive}` | 已对齐（形态不同） | `lib/app/maintenance_bootstrap.dart`、`lib/services/initialization/initialization_maintenance.dart` |
| 密码登录门 | `app/login/**`、`api/auth/login` | **刻意舍弃** | — |
| 排行榜（多用户） | `modules/leaderboard/service.ts`、`components/leaderboard-panel.tsx` | 已对齐（单用户本地榜） | `game_high_scores` 表、`lib/features/games/widgets/game_result_panel.dart` |

---

## 3. 今日（仪表盘）

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 今日队列三卡（到期复习 / 错词强化 / 新词学习） | `app/(main)/page.tsx` | 已对齐 | `lib/features/dashboard/cards/today_plan_card.dart` |
| 概览指标（词条数 / 掌握 / 已初始化 / 失败） | 同上 | 已对齐 | `lib/features/dashboard/cards/statistics_card.dart` |
| 每日 AI 建议（含质量分与重点复习入口） | `daily-ai-suggestion.tsx`、`api/suggestions/today` | 已对齐 | `lib/features/dashboard/cards/suggestion_card.dart`、`lib/services/suggestion_service.dart` |
| 「继续上次学习」卡片 | `page.tsx:142` | 已对齐 | `lib/features/dashboard/cards/resume_session_card.dart` |
| 趣味训练入口（4 小游戏 + 配对 + 音标） | `page.tsx` | 已对齐 | `lib/features/dashboard/cards/practice_card.dart` |
| 平台能力提示 | — | 本版新增 | `lib/features/dashboard/cards/platform_card.dart` |

---

## 4. 单词本

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 列表 + 分页（每页 40） | `words/page.tsx` | 已对齐 | `lib/features/words/words_page.dart`、`widgets/word_paginator.dart` |
| 搜索（词条 / 归一化词形 / 备注三列） | `words/page.tsx`、`modules/words/queries.ts` | 已对齐 | `lib/data/db/daos/word_dao.dart` |
| 掌握状态筛选 | 同上 | 已对齐 | `lib/features/words/widgets/word_filter_controls.dart` |
| 初始化状态筛选 | 同上 | 已对齐 | 同上 |
| 特殊筛选：仅错词 / 仅到期 / 仅暂停（可叠加） | 同上 | 已对齐 | 同上 |
| 五种排序（导入时间 / 收藏时间 / 字母 / 熟练度 / 到期时间） | 同上 | 已对齐 | `WordSort`（`lib/data/db/daos/word_dao.dart`） |
| 到期排序时无复习卡的词条排最后 | 同上 | 已对齐 | 同上（显式 NULLs last） |
| 掌握概览条 + 「详细统计」入口 | `words/learning-overview.tsx` | 已对齐 | `lib/features/words/widgets/mastery_overview_strip.dart` |
| 空库 / 被筛空两种空态 | `words/page.tsx` | 已对齐 | `lib/features/words/widgets/word_empty_view.dart` |
| 卡片朗读发音 | `words/page.tsx` | 已对齐 | `lib/features/words/widgets/word_card.dart` |
| 卡片编辑词条弹窗 | `words/page.tsx` → `EditWordDialog` | 已对齐 | `lib/features/word_detail/dialogs/edit_word_dialog.dart` |
| 窄屏筛选面板 | `words/page.tsx` | 已对齐 | `lib/features/words/widgets/word_filter_sheet.dart` |

---

## 5. 词条详情

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 头部：词条、音标、口音、掌握度、来源时间 | `words/[id]/components/word-header.tsx` | 已对齐 | `lib/features/word_detail/cards/word_detail_header_card.dart` |
| 释义卡 + 手工释义编辑 | `definitions-card.tsx` | 已对齐 | `cards/definitions_card.dart` |
| 例句卡（朗读 / AI 翻译 / 删除） | `examples-card.tsx` | 已对齐 | `cards/examples_card.dart` |
| 短语搭配卡 | `extended-content-card.tsx` | 已对齐 | `cards/phrases_card.dart` |
| 词形变化卡 | 同上 | 已对齐 | `cards/forms_card.dart` |
| 同义 / 反义 / 词族 / 易混词卡 | 同上 | 已对齐 | `cards/related_words_card.dart` |
| 词根词缀卡 | 同上 | 已对齐 | `cards/morphology_card.dart` |
| 摘要卡 | 同上 | 已对齐 | `cards/summary_card.dart` |
| 句子解析卡 | `sentence-analysis-card.tsx` | 已对齐 | `cards/mnemonic_card.dart`（`_AnalysisSection`） |
| 助记卡（AI 生成） | `learning-card.tsx`、`api/words/[id]/mnemonic` | 已对齐 | `cards/mnemonic_card.dart` |
| 侧栏：学习情况（FSRS + 错词） | `word-sidebar.tsx` | 已对齐 | `cards/learning_snapshot_card.dart` |
| 侧栏：笔记 | 同上 | 已对齐 | `cards/note_card.dart` |
| 侧栏：初始化质量（数据源调用记录） | 同上 | 已对齐 | `cards/initialization_quality_card.dart` |
| 侧栏：复习历史 | 同上 | 已对齐 | `cards/review_history_card.dart` |
| 有道预览 / 应用（两种模式） | `youdao-preview-dialog.tsx`、`modules/words/youdao-refresh.ts` | 已对齐 | `lib/services/word_content_refresh_service.dart`、`dialogs/youdao_preview_dialog.dart` |
| 编辑词条（改名 + 重取词典 + 应用） | `edit-word-dialog.tsx`、`modules/words/mutations.ts:29` | 已对齐 | `lib/features/word_detail/dialogs/edit_word_dialog.dart`、`WordEditService.updateContent` |
| 关联词预览 + 加入词库 | `related-word-dialog.tsx`、`modules/words/related.ts` | 已对齐 | `lib/services/related_word_service.dart`、`dialogs/related_word_dialog.dart` |
| 「补全缺失内容 / 重新生成」 | `word-header.tsx`、`api/words/[id]/initialize` | 已对齐 | `cards/word_detail_header_card.dart` |
| 暂停 / 恢复学习 | `word-header.tsx` | 已对齐 | 同上 |
| 删除词条（二次确认 + 学习历史保护） | `word-header.tsx`、`modules/words/related.ts:deleteWord` | 已对齐 | 同上、`WordEditService.delete` |
| 真人录音优先朗读（有道 mp3 + 系统兜底） | `modules/tts/service.ts`、`api/tts/youdao` | 已对齐 | `lib/services/audio/word_speaker.dart` |
| AI 翻译缺失释义 / 摘要 / 例句（写库前重读最新 JSON） | `modules/translations/service.ts` | 已对齐 | `lib/services/initialization/supplemental_tasks.dart`（`translationBatchLimit` 条一批） |
| 词条改名时重取词典内容 | `modules/words/mutations.ts:29` | 已对齐 | `WordEditService.updateContent`（单事务） |

---

## 6. 学习会话

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 8 种题型的作答控件 | `study/study-client.tsx` | 已对齐 | `lib/features/study/**`（13 个组件） |
| 四档自评即提交 | 同上 | 已对齐 | `lib/features/study/study_rating.dart` |
| 选择题揭示答案延迟（可设置） | 同上 | 已对齐 | `study_choice_options.dart` |
| 拼写题「提示」（渐进式揭示） | `study-client.tsx:55-70,588,732` | 已对齐 | `lib/domain/review/hint.dart`、`lib/features/study/study_hint_bar.dart` |
| 用提示后评级降级为「模糊」 | `study-client.tsx:397` | 已对齐 | `lib/features/study/study_providers.dart` |
| 字符级答案 diff | `components/answer-diff.tsx` | 已对齐 | `lib/domain/review/answer_diff.dart`、`study_feedback.dart` |
| 四档评级上的 FSRS 间隔预览 | `study-client.tsx:344`、`api/reviews/preview` | 已对齐 | `ReviewService.previewIntervals`、`study_interval_preview.dart` |
| 活跃计时（失焦 / 隐藏 / 45 秒空闲暂停） | `lib/use-active-stopwatch.ts` | 已对齐 | `lib/features/study/study_clock.dart` |
| 后续 5 题音频预取 | `study-client.tsx:105` | 已对齐 | `WordSpeaker.preloadBatch` |
| 键盘快捷键（1-4 评分 / Space 检查 / R 重播 / S 稍后再学） | `study-client.tsx:462-541` | 已对齐 | `lib/features/study/study_page.dart`（`_ratingKeys` / `_handleKey`） |
| 跳过（稍后再学） | `study-client.tsx` | 已对齐 | `study_progress_header.dart`、`StudyService.skipItem` |
| 会话总结 | 同上 | 已对齐 | `study_feedback.dart` |
| 无限学习 / 新一轮 | 同上 | 已对齐 | `study_providers.dart` |

---

## 7. 添加与导入

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 手动输入单个词条（离线可填） | `add/manual-tab.tsx` | 已对齐 | `lib/features/add/widgets/manual_entry_form.dart` |
| 手动批量：多行粘贴 → 词典逐行预览 → 逐行确认 | `add/manual-tab.tsx`、`modules/manual/**` | 已对齐 | `lib/services/manual_preview_service.dart`、`lib/features/add/widgets/manual_batch_panel.dart` |
| 手动批量：内容类型自动判断 + 语言选择 | 同上 | 已对齐 | 同上 |
| 粘贴文章 · AI 选词（分段 → 候选 → 预览/合并 → 提交） | `add/article-tab.tsx`、`modules/article-import/**` | 已对齐 | `lib/domain/article_import/**`、`lib/services/article_import/**`、`lib/features/add/article_page.dart` |
| 文章导入：AI 失败/未配置时回退本地筛选并显示原因 | `article-import/ai-select.ts` | 已对齐 | `lib/services/article_import/**` |
| 文章导入：重置本次已有词条的学习进度 | `article-tab.tsx:475,526` | 已对齐（与 CSV 同一约定） | `lib/ui/widgets/reset_progress_option.dart`、`ArticleImportService.commit` |
| 文章导入：入队后把无释义词条标成 `QUEUED` | `imports/commit.ts:31-36` | 已对齐 | `WordEditService.markInitializationQueuedIfNoDefinition` |
| CSV 导入：选择文件 → 预览 → 三种策略 → 提交 | `add/csv-tab.tsx`、`modules/imports/**` | 已对齐 | `lib/services/csv_import_service.dart`、`lib/features/import/**` |
| CSV：EasyDict 列名别名与宽松匹配 | `modules/imports/normalizer.ts` | 已对齐 | `lib/data/import/**` |
| CSV：只看问题行过滤 | `add/csv-tab.tsx` | 已对齐 | `lib/features/import/import_preview_table.dart` |
| CSV：批次历史 + 撤销（含依赖阻断） | `modules/imports/rollback.ts` | 已对齐 | `lib/features/import/import_history_section.dart` |
| CSV：重置本次已有词条的学习进度 | `api/imports/commit` | 已对齐 | `lib/ui/widgets/reset_progress_option.dart` |
| 导入完成后的「查看初始化 / 打开单词本 / 继续导入」 | `add/csv-tab.tsx` | 已对齐 | `lib/features/import/import_page.dart`（`_ResultActions`） |
| CSV 拖拽上传 | `add/csv-tab.tsx` | **已知差异** | 见 §12 |

---

## 8. 初始化队列

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 队列列表 + 进度 | `initialize/initialize-progress.tsx` | 已对齐 | `lib/features/initialize/widgets/queue_progress_card.dart` |
| 按词条查看记录（展开子任务、重试次数、失败原因、行内操作） | `initialize/initialize-word-list.tsx` | 已对齐 | `widgets/queue_list.dart` |
| 配置初始化（字段 / 数据源 / 覆盖策略 / 范围 / 预览） | `initialize/initialization-configurator.tsx` | 已对齐 | `lib/features/initialize/configurator/**` |
| 批量选择（选择当前页 / 取消选择 / 批量重试） | `initialize/page.tsx` | 已对齐 | `widgets/queue_bulk_bar.dart` |
| 创建任务 / 刷新 / 重试失败 | `initialize/page.tsx` | 已对齐 | `widgets/queue_toolbar.dart` |
| 任务详情：数据源调用记录 / 已获取字段 / 错误信息 | `initialize/job-detail-dialog.tsx` | 已对齐（位置不同） | 词条详情页的初始化质量卡（`cards/initialization_quality_card.dart`） |
| 立即处理一批（不等定时器） | — | 本版新增 | `widgets/queue_toolbar.dart` |

---

## 9. 统计

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 概览指标 | `statistics/page.tsx` | 已对齐 | `lib/features/statistics/widgets/overview_cards.dart` |
| 趋势图 + 档位（7 / 30 / 90 / 一年） | 同上 | 已对齐 | `widgets/trend_chart_card.dart`、`trendDayOptions` |
| 刷新按钮 | 同上 | 已对齐 | `statistics_page.dart` |
| 熟练度分布 | 同上 | 已对齐 | `widgets/mastery_distribution_card.dart` |
| 题型正确率 | 同上 | 已对齐 | `widgets/question_type_card.dart` |
| 最近学习明细（按天：复习 / 正确 / 正确率 / 忘记 / 稍后再学 / 有效时长 / 会话；倒序取 30 天；窄屏卡片 + 宽屏表格） | 同上 | 已对齐 | `widgets/recent_daily_detail_card.dart`、`StatisticsDao.dailyTrend` |
| 最近作答明细 | 同上 | 已对齐 | `widgets/recent_results_card.dart` |

---

## 10. 设置 / 游戏 / 配对 / 音标

| 旧版能力 | 旧版位置 | Flutter 状态 | Flutter 位置 |
|---|---|---|---|
| 学习计划（新词量 / 错词上限 / 到期上限 / 目标保留率 / AI 重试） | `settings/study-plan-settings.tsx` | 已对齐 | `lib/features/settings/study_plan_section.dart` |
| 题型开关与权重 | `settings/question-type-settings.tsx` | 已对齐 | `question_type_section.dart` |
| 播放设置（口音 / 三种语速 / 自动朗读 / 揭示延迟） | `settings-shared.tsx` | 已对齐 | `playback_section.dart` |
| 真人录音总开关 | — | 本版新增 | `playback_section.dart` |
| 数据源开关与 Key | `settings/provider-card.tsx` | 已对齐 | `providers_section.dart` |
| 词库设置（词汇量档位 / 考试目标） | `settings/study-settings-tab.tsx` | 已对齐 | `vocabulary_section.dart` |
| AI 设置（provider 增删改 / 模型选择 / 参数 / 连通性测试） | `settings/ai-settings-tab.tsx`、`ai-config-card.tsx`、`model-picker-dialog.tsx` | 已对齐 | `settings/ai/**` |
| 数据管理（备份导出 / 导入 / 重置） | `settings/data-settings-tab.tsx`、`api/backups/**` | 已对齐 | `data_management_section.dart`、`lib/services/backup/**` |
| 4 个小游戏（拼图 / 地鼠 / 堆堆乐 / 俄罗斯方块） | `games/*.tsx` | 已对齐 | `lib/features/games/**`、`lib/domain/games/**` |
| 听音辨词 / 词义冲刺 | `games/page.tsx:297-310` | 已对齐 | 同上 |
| 游戏 HUD（倒计时 / 得分 / 连击 / 失误 / 退出） | `components/game-hud.tsx` | 已对齐 | `widgets/game_shell.dart` |
| 重点复习词标记 | `games/page.tsx:283` | 已对齐 | `games_play_view.dart` |
| 结算（得分 / 正确率 / 连击 / 错词清单） | `components/game-result.tsx`、`game-summary.tsx` | 已对齐 | `widgets/game_result_panel.dart` |
| 结算错词可点开查看 | `game-summary.tsx`、`game-mistake-flashcards.tsx` | 已对齐 | 同上 |
| 单机高分榜 | `modules/leaderboard/service.ts` | 已对齐 | `game_high_scores` 表 |
| 限时配对 | `match/page.tsx`、`modules/matching/service.ts` | 已对齐 | `lib/features/match/**` |
| 音标训练（48 音标 / 三种题型 / 发音要领 / 口型 / 易踩坑） | `phonetics/**` | 已对齐 | `lib/features/phonetics/**`、`lib/domain/phonetics/**` |

---

## 11. 刻意舍弃（有明确理由，不是缺口）

| 项 | 旧版 | 本版 | 理由 |
|---|---|---|---|
| 密码登录门 | `app/login/**` + `api/auth/login` + 服务端会话 | 无 | 单用户纯本地应用没有账号概念；数据就在本机，登录门只增加一次无意义的输入 |
| 腾讯云 TMT 翻译 provider | `modules/dictionary/providers/tencent-translate.ts` + TC3 签名 | 无 | 需要把 SecretKey 内嵌进客户端，反编译即泄露；翻译交给 AI 兜底 |
| 服务端 TTS 端点与内存 LRU 语义 | `api/tts/route.ts`（Edge TTS WebSocket） | 系统 TTS（`flutter_tts`）+ 真人录音 + 本地 LRU | 纯本地应用没有服务端进程；macOS 的 `flutter_tts` 不支持 `synthesizeToFile`，双端能力不对等 |
| 服务端预览表（`manual_previews` / `import_previews` 的令牌与 TTL） | `modules/manual/storage.ts`、`modules/imports/preview.ts` | 手动批量预览**存内存**（带 TTL，重启即失效）；CSV 预览落 `import_batches` | 单用户单进程没有并发认领问题，令牌与 TTL 是为多请求竞争服务的 |
| 固定服务端时区 `APP_TIMEZONE=Asia/Shanghai` | `lib/date-key.ts` | 设备本地时区 | 纯本地应用没有服务端时区概念 |

---

## 12. 已知差异（能做但选择不做，或形态不同）

| 项 | 差异 | 影响 | 理由 |
|---|---|---|---|
| CSV 拖拽上传 | 旧版支持拖拽到区域，本版只有文件选择器 | 桌面端少一种入口 | 需要引入额外插件（`desktop_drop`），而文件选择器已覆盖同一需求，且移动端没有对应交互；为单一入口引入依赖不划算 |
| 初始化任务详情的位置 | 旧版在队列页弹窗里看数据源调用记录，本版在词条详情页的「初始化质量」卡里看 | 排查路径不同 | 调用记录属于**词条**的审计信息而不是某个任务的；放在词条上可以从任何入口到达，队列页仍保留任务级的重试次数与失败原因 |
| 浏览器（Web）端的数据源抓取 | 有道（主/备/发音）、爱词霸在浏览器里被同源策略挡下 | Web 端这几个数据源不可用 | 浏览器不允许网页跨域抓取第三方页面，除非自建代理；本版不搭代理，而是抛出 `BROWSER_CORS_BLOCKED` 并提示改用桌面/移动端。**实测**（Chromium 149 + release 产物）：Merriam-Webster 词典 API 与音频 CDN、MyMemory、LLM 网关均带 CORS 头可用；`dictionaryapi.dev` 因本机网络不可达未能测定 |
| 同步 AI 助记 | 旧版学习页可 `sync:true` 当场生成助记，本版统一走初始化队列 | 需要等队列推进 | 同步生成会让一次点按占用一次完整 LLM 往返（默认超时 3 分钟）；统一走队列后，界面不必为它维护第二套加载/超时/降级状态 |
| 单条例句的同步翻译 | 旧版 `translateExample` 直接返回译文，本版入队 `EXAMPLE_TRANSLATIONS` | 需要等队列推进 | 同上；且批量与单条共用同一条翻译路径，避免两套实现给出两种译文 |
| 学习页题库为空时的行为 | 旧版无选项的题只能「稍后再学」，本版保留同样的限制 | — | 语义一致，仅记录以免被误认为缺陷 |
