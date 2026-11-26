# LexiLoop 远程备份（WebDAV）

把「设置 → 数据管理」里的 JSON 备份接到**用户自建的 WebDAV**（坚果云、群晖、
Nextcloud、Apache `mod_dav`、rclone serve 等）上。三件事：

1. **手动上传**：一键把当前全量 JSON 备份 `PUT` 到远端目录；
2. **从远端恢复**：列出远端备份，选一份下载并全量恢复；
3. **自动备份**：按周期检查，**数据确实变了才上传**。

本版对应代码：

| 层 | 文件 |
| --- | --- |
| 协议 | `lib/data/remote_backup/webdav_client.dart`、`webdav_multistatus.dart` |
| 端口 | `lib/data/remote_backup/remote_backup_client.dart` |
| 服务 | `lib/services/remote_backup/webdav_{upload,restore,auto_backup,state_store}.dart` |
| 装配 | `lib/services/remote_backup/webdav_providers.dart` |
| 界面 | `lib/features/settings/remote_backup_section.dart` |
| 模型 | `lib/domain/models/webdav_settings.dart` |

---

## 1. 怎么配

设置 → 数据管理 → **远程备份（WebDAV）**，填四项：

| 字段 | 例子 | 说明 |
| --- | --- | --- |
| 服务器地址 | `https://dav.example.com/dav` | 必须带 `http(s)://`；尾斜杠会被去掉 |
| 备份目录 | `/LexiLoop` | 留空 = 服务器根目录；不存在时会逐级 `MKCOL` 创建 |
| 账号 | `leo` | |
| 密码 | 应用专用密码 | **多数服务不能用登录密码**，见下 |

> **为什么强调「应用专用密码」**：坚果云、群晖 DSM、Nextcloud 对第三方客户端
> 普遍要求单独生成的密码（坚果云：账户信息 → 安全选项 → 添加应用密码）。
> 直接填登录密码会得到 401，界面上的文案与错误提示都点明了这一点。

自动备份周期可选：关闭 / 每 6 小时 / 每天（默认）/ 每 3 天 / 每周。

**密码的存放**：只写在本机 `settings` 表里（与 Merriam-Webster API Key、
LLM 配置同一处）。**导出的备份文件里不含它**——见 §4。

---

## 2. 三条链路的语义

### 2.1 手动上传

```
读设置 → 导出全量 JSON → PROPFIND 目录（不存在则 MKCOL 逐级创建）→ PUT
```

- 文件名与本地导出**逐字一致**：`lexiloop-backup-YYYY-MM-DD-HHmmss.json`
  （命名唯一来源：`lib/services/backup/backup_naming.dart`）。
- 每次上传都带**新时间戳**，因此不会覆盖历史备份。
  唯一的例外是同一秒内的两次上传——秒是文件名的最小粒度。
- **只读数据库**：失败重试不会损坏任何本地数据；失败只写一行状态。
- 上传前要求敲 `UPLOAD` 确认（与本地导出同一力度：外发一份副本，但不改本地）。

### 2.2 从远端恢复

```
PROPFIND（Depth: 1）→ 列表（只收 lexiloop-backup-*.json）→ GET → decodeUtf8
  → BackupImporter.import（单事务全量替换 12 张表）→ 失效全部读库缓存
```

- 与本地导入**完全同一条**导入路径，只是多了一步下载。
- 确认门槛比导出更高：必须敲 `RESTORE`，文案明说「整体替换、无法撤销」。
- 导入在单事务内完成；失败时原数据不变。
- 恢复会整体替换 `settings` 表，因此**远端配置也会回到备份里的版本**；
  由于备份里的密码已被剥掉，恢复后需要在设置页重新填一次密码。

### 2.3 自动备份

不是 `Timer.periodic`，而是「按 5 分钟一次的检查节奏醒来，每次重新判断」：

```
未启用（周期 0）           → 什么都不做（不挂定时器、不发请求）
从未成功过                 → 视为到期；数据检查点必然视为「变了」→ 上传
距离上次成功 < 周期         → 只排下一次检查
距离上次成功 ≥ 周期 且 检查点没变 → 跳过（不浪费一次 27MB 上传）
距离上次成功 ≥ 周期 且 检查点变了 → 上传一份
```

- **数据检查点**是实际导出表数据的稳定 SHA-256 指纹，而不是只抽查作答时间与词条数；词条内容、设置、任务等任何导出数据改变都会使它变化。计算会排除信封中的 `exportedAt`，并归一化 WebDAV 备份自身的运行状态，避免成功回写后自触发下一轮上传。
- 指纹只在备份周期到期时计算。到期时导出的同一份快照用于比较、PUT 上传和成功检查点记录，避免导出与检查点查询之间发生写入时，把尚未上传的数据误记成已备份。旧版 `时间戳:词条数` 检查点会视为无有效指纹，触发一次完整备份。
- 排期用一次性定时器（`lib/services/scheduling/one_shot_timer.dart`），
  每次唤醒后按**当时读到的**设置重算间隔，因此改配置立刻生效、无需重启。
- **失败不打扰用户**：自动备份失败只把错误码写进设置行，设置页的状态行显示它；
  未分类异常也记录 `WEBDAV_UNEXPECTED_FAILURE`，不再静默丢失失败原因。
  不弹 SnackBar（用户可能正在答题）。
- 重入保护：上一轮上传没结束时不会再叠一轮（27MB 上传可能超过检查间隔）。

---

## 3. 失败模式与错误码

| 场景 | 错误码 | 可重试 | 用户看到 |
| --- | --- | --- | --- |
| 地址/账号/密码没填齐 | `WEBDAV_NOT_CONFIGURED` | 否 | 请先填写 WebDAV 地址、账号与密码。 |
| 401 / 403 | `WEBDAV_AUTH_FAILED` | 否 | 拒绝登录，并提示多为「应用专用密码」 |
| 连不上 / 超时 | `WEBDAV_UNREACHABLE` | 是 | 无法连接服务器，请检查地址与网络 |
| 其他非 2xx（含 507 空间不足） | `WEBDAV_REQUEST_FAILED` | 5xx 为是 | 请求失败，请稍后重试 |
| 备份文件 / 目录已被删除 | `WEBDAV_NOT_FOUND` | 否 | 远端目标不存在 |
| 远端目录里没有备份 | `WEBDAV_NO_BACKUPS` | 否 | 没有找到 LexiLoop 备份文件 |
| 备份超过 100MB | `BACKUP_TOO_LARGE` | 否 | 备份文件过大（列表声明与实际长度各校验一次） |
| 下载内容不是合法 UTF-8 / JSON | `BACKUP_INVALID_FORMAT` / `BACKUP_INVALID_JSON` | 否 | 与本地导入同一套文案 |

**浏览器（Web 构建）**：被同源策略挡下时抛 `BROWSER_CORS_BLOCKED`
（「请改用桌面端或移动端」），而不是伪装成「网络不可用」——复用
`lib/data/dictionary/http_fetcher.dart` 里同一条映射。

---

## 4. 两个刻意的取舍

### 4.1 导出的备份里没有 WebDAV 密码

`BackupExporter` 在导出 `settings` 表时会剥掉 `webdavBackup.password`
（实现见 `lib/data/backup/backup_export.dart` 的 `_stripSecrets`）。

理由：这份文件**会被上传到该 WebDAV 服务器本身**，还可能被分享给别人。
把服务器自己的密码写进上传到该服务器的文件里，等于把凭据交给服务器与任何
拿到备份的人。剥掉之后，远端恢复会带回地址与账号，只需补密码。

**`llmConfig` 里的 API Key 保持原样**：备份的主要用途之一就是换机迁移，
而那把 Key 的用途与备份的去处无关。

### 4.2 不做远端保留策略

本版**不会删除**远端任何文件。上 N 次就积累 N 份（同名那一秒除外），
代价是占用空间，收益是绝不出现「程序替我删了备份」。需要清理时请手动删。

---

## 5. 已知限制

1. **无断点续传**：上传超时（默认 5 分钟）后只能整体重试。
2. **无冲突检测**：不用 ETag / `If-Match`，同一秒的两次上传后者覆盖前者。
3. **无增量备份**：每次上传都是全量（与本地导出一致）。
4. **密码不在安全存储里**：与现有 API Key 同样落在 `settings` 表。
   桌面端 macOS 由 App Sandbox 与应用支持目录权限保护，但**没有**接钥匙串。
5. **Web 端成功率取决于服务器是否发 CORS 头**：多数自建服务默认不发。
   另外 `PROPFIND` / `MKCOL` 属于非简单方法，浏览器一定会先发预检请求，
   服务器必须同时对 `OPTIONS` 回 CORS 头。
6. **恢复会重置远端配置本身**（见 §2.2）。
7. **明文 HTTP（`http://`）在 Android 上未实测**：Android 9 起默认禁止明文流量，
   `dart:io` 的 `HttpClient` 会遵守该策略。内网 NAS 若只有 http，
   可能需要在 `AndroidManifest.xml` 里开 `usesCleartextTraffic`
   （影响全应用的网络策略，因此没有默认打开）；有 https 时请优先用 https。
   macOS 与桌面端未受影响，但同样建议用 https。
   **局域网同步（`docs/LAN_SYNC.md`）必然走明文 http，会先撞上这一条**——
   若那边确认需要加 network security config，这里也一并受益。
8. **恢复只有全量替换，没有合并**：合并模式目前只接在局域网同步上
   （`BackupMergeService` 与传输无关，接过来只是多一处装配）。
   需要合并时请用 `docs/LAN_SYNC.md` §6 的流程。

---

## 6. 测试

全部离线，不碰真网络：

```bash
flutter test test/data/remote_backup/            # 协议：方法/路径/认证头/207 解析/状态码映射
flutter test test/domain/models/webdav_settings_test.dart
flutter test test/services/remote_backup/        # 上传/恢复/自动备份/排期
flutter test test/features/settings/remote_backup_section_test.dart
flutter test test/data/backup/backup_export_secret_test.dart  # 密码剥离
flutter test test/app/maintenance_bootstrap_test.dart         # 启动点火
```

两层假替身，各自负责一段：

- `test/support/recording_dio_adapter.dart` 替换 `dio` 的 `HttpClientAdapter`，
  于是「真的按 WebDAV 说话」这件事能被断言（`PROPFIND` + `Depth`、
  目录尾斜杠、`MKCOL` 405 幂等、Basic 认证头、字节请求体）；
- `test/support/fake_remote_backup_client.dart` 替换端口，
  于是上传/恢复/自动备份的业务分支不必伪造 HTTP。

### 6.1 真实 HTTP 的端到端验证（可选但强烈建议）

上面那些用例都替换了 `dio` 的传输层，因此「请求符合 WebDAV」是被断言的，
而「真的能和一台 WebDAV 服务器谈下来」由一条开关式用例覆盖。仓库自带一个
只用标准库的最小 WebDAV 服务器：

```bash
# 起一个本地 WebDAV（只实现 PROPFIND / MKCOL / PUT / GET）
python3 tool/webdav_test_server.py 8765 /tmp/lexiloop-dav-root &

LEXILOOP_WEBDAV_SMOKE_URL=http://127.0.0.1:8765 \
  flutter test test/data/remote_backup/webdav_live_smoke_test.dart
```

它跑完整链路：建目录 → 上传 → 列目录 → 下载（断言与上传**逐字节相同**）
→ 导入另一个库 → 断言行数与词条；另含「密码错 → 鉴权失败」「文件不存在 →
notFound」「多级目录逐级 MKCOL」。

也可以指向真实服务（坚果云 / 群晖 / Nextcloud）：额外设置
`LEXILOOP_WEBDAV_SMOKE_USER` / `LEXILOOP_WEBDAV_SMOKE_PASSWORD`。
该用例只追加、不删除任何远端文件。

**真机手测清单**（改协议相关代码后请至少走一遍）：

1. 填错密码 → 测试连接 → 应看到「应用专用密码」的提示；
2. 填对 → 测试连接 → 立即上传 → 远端出现带时间戳的 `.json`；
3. 换一台设备（或清空本地数据）→ 从远端恢复 → 词条与复习记录回来；
4. 周期设「每 6 小时」→ 重启应用 → 已上传过且数据没变时**不产生新文件**；
5. 答题若干 → 等周期到（或改系统时间）→ 产生新的一份。
