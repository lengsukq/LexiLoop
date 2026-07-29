# LexiLoop 词环

LexiLoop 是一个私人向、单用户、自托管的词汇复习应用。它导入 EasyDict Favorites CSV，只保存并初始化用户实际收藏的词条，不构建完整业务词典库。

## 已实现

- EasyDict CSV 预览、校验、文件内去重、三种重复导入策略和安全批次撤销
- OpenAI-compatible / Anthropic AI 词条初始化：生成分词义释义、例句、搭配、词形、同根词、词根词缀、近反义词、易混词和学习提示
- DictionaryAPI.dev 与可选 ECDICT 作为音标、真人音频和离线词形补充；Edge TTS 独立负责免费发音
- 独立初始化 Worker、任务锁、心跳、超时恢复、退避重试和失败重试
- FSRS 间隔重复、稳定答案幂等、同题防重复、跨日错词强化、熟练度和掌握状态
- 去重后的今日队列、新词、到期复习、错词、听力拼写和中文拼写
- 24 小时内会话恢复、稍后再学和过期会话自动释放
- 单词本、手动释义、AI 质量/Token 记录、统计趋势、设置；生成的近义词、反义词、同根词和易混词可点击预览并一键加入初始化
- SQLite / JSON 导出与校验后恢复
- Docker Compose 部署到 FNOS

## 本地开发

```bash
cp .env.example .env
corepack enable
yarn install --frozen-lockfile
yarn db:migrate
yarn dev
```

另开终端启动 Worker：

```bash
yarn worker
```

质量检查：

```bash
yarn check
```

## Docker / FNOS

```bash
cp .env.example .env
# 可选：在 .env 中设置 LEXILOOP_PASSWORD；留空则不启用登录密码
docker compose up -d --build
```

访问 `http://FNOS_IP:3000`。持久数据保存在 `./data`。

如果在 `.env` 中设置了 `LEXILOOP_PASSWORD`，进入 LexiLoop 页面时需要输入密码；不需要用户名。登录状态默认保留 7 天。修改或移除密码后，重新创建 app 容器使新的运行时环境变量生效：

```bash
docker compose up -d --force-recreate app
```

密码只在容器运行时注入，不会写入 SQLite 数据库。

恢复 SQLite 备份后，页面会提示重启：

```bash
docker compose restart app worker
```

## EasyDict CSV

必要列：

```csv
queryText,queryFromLanguage,queryToLanguage,timestamp
cotton,English,Simplified Chinese,2026-07-27T08:00:00Z
```

## AI 词条初始化

在「设置 → 大模型配置」中启用 **AI 词条初始化**，配置提供商、Base URL、API Key 和模型。支持 OpenAI-compatible 接口、SiliconFlow、自定义兼容接口和 Anthropic。

AI 只生成结构化学习内容，不生成音频 URL。实际发音继续由 Edge TTS 按需生成。AI 返回内容会经过严格 JSON Schema、Zod 业务校验、词条一致性检查和质量评分；模型、Token、提示词版本和质量分会记录在初始化历史中。强制刷新不会覆盖用户手动释义。

词条详情中的近义词、反义词、同根词和易混词可以点击查看说明和词库状态；未加入时可一键创建词条并进入初始化队列。初始化页面还可以批量补齐所有尚未经过 AI 的旧词条，或在确认 Token 风险后强制重新生成全部词条。

## 数据源说明

LexiLoop 不将有道完整词典 API 结果写入长期缓存，因为相关官方条款与本项目长期写入 SQLite、反复学习的需求冲突。默认使用允许该使用方式的公开数据源和本地 ECDICT。

完整架构见 [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)。
