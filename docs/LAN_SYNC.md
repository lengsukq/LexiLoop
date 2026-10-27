# LexiLoop 局域网同步（LAN Sync）

把「设置 → 数据管理」里的同步能力从「经服务器中转」扩到「局域网直连」：
一台设备开启**共享**（内嵌只读 HTTP 服务端），同网段的另一台设备**自动发现**
它、输入主机屏幕上显示的 **6 位配对码**、然后二选一：

- **合并**（默认）：把对方的词条与作答**并进**本机，本机现有数据一条不删；
- **覆盖**：用对方的整份备份**整体替换**本机。

本版对应代码：

| 层 | 文件 |
| --- | --- |
| 协议（路径 / 请求头 / 握手体） | `lib/data/lan_sync/lan_sync_protocol.dart` |
| 端口（服务端 / 发现器 / 客户端） | `lib/data/lan_sync/lan_sync_{host_port,discovery_port,client}.dart` |
| 平台实现 | `lan_sync_host_{native,web}.dart`、`lan_sync_discovery_{native,web}.dart`（条件导出见同名不带后缀文件） |
| HTTP 客户端 | `lib/data/lan_sync/lan_sync_client_dio.dart` |
| 服务 | `lib/services/lan_sync/lan_sync_{state_store,share_service,pull_service,providers}.dart` |
| 界面 | `lib/features/settings/lan_sync_section.dart`（挂在「数据管理」tab） |
| 模型 | `lib/domain/models/lan_sync_settings.dart` |

---

## 1. 怎么用

### 1.1 在**有数据**的那台设备上开启共享

设置 → 数据管理 → **局域网同步** → 「开启共享」。界面会给出：

- **6 位配对码**（每次开启共享都重新生成，只存在内存里）；
- 一个 `http://<本机局域网地址>:<端口>/` 地址；
- 一个「已服务 N 次」的计数——主机是纯被动的一方，这是「对方真的连上了」的
  唯一反馈。

共享期间设备名与端口**不可修改**：改端口不会对已经监听的套接字生效，
「改了没反应」比「不能改」更难理解。

### 1.2 在另一台设备上拉取

设置 → 数据管理 → 局域网同步 → 选「同步方式」→ 「搜索设备」→ 选中一台 →
输入配对码 → 确认。

| 同步方式 | 会发生什么 | 确认门槛 |
| --- | --- | --- |
| **合并**（默认） | 对方的词条、词典内容、作答流水、会话历史并进本机；本机的**一条都不删** | 普通确认框 |
| **覆盖** | 本机的词条、学习记录、导入历史与设置被整份替换 | 必须敲 `RESTORE` |

选择是**持久化**的：它跨重启保留，因此同步几次之后不必每次重选。

端口默认 `8765`，被别的程序占用时改成任意 `1024–65535` 的值即可。

---

## 2. 协议

服务标识 `lexiloop-lan-sync`，协议版本 `1`。

### 2.1 HTTP（主机监听 `0.0.0.0:<port>`）

```
GET /lexiloop/v1/handshake
    头  LexiLoop-Sync-Code: <6 位数字>
    200 {"service":"lexiloop-lan-sync","version":1,"device":"<设备名>"}
    401 配对码不对

GET /lexiloop/v1/backup
    头  LexiLoop-Sync-Code: <6 位数字>
    200 body = 备份 JSON 字节
        Content-Type: application/json
        Content-Length: <n>
        X-LexiLoop-Backup-Name: lexiloop-backup-YYYY-MM-DD-HHmmss.json
        X-LexiLoop-Backup-Rows: <总行数>
    401 配对码不对 / 404 对方已停止共享 / 409 已有一次同步在进行
    413 备份超过 100MB / 500 导出失败（响应体带 {"error":"<CODE>"}）

其它路径或非 GET 方法 → 404 / 405
```

- **先验码、再导出**：否则同网段任何人都能用一次请求逼出一次 27MB 的导出。
- **一次拉取只导出一次**：不预先缓存，避免「开了共享但没人来拉」也占着内存，
  也避免缓存的那份落后于最新数据。
- **同一时刻只服务一个请求**：导出一次 27MB 已经要吃满 I/O，并发只会让两边都慢。

### 2.2 UDP 发现（主机监听 `0.0.0.0:<discoveryPort>`，默认 8766）

```
请求  {"service":"lexiloop-lan-sync","version":1,"kind":"query"}
响应  {"service":"lexiloop-lan-sync","version":1,"kind":"reply",
       "instanceId":"<每次开启共享随机生成>","device":"<设备名>","port":8765}
```

- 应答**单播**回请求方，不广播：同网段每台机器都解析一份与自己无关的报文没有意义。
- 非本协议、非本版本、非 JSON 的报文一律忽略（一个畸形的邻居不该打断整次搜索）。
- 发现端口固定、用户不可配置：它只是「敲门」，真正的连接与鉴权在 TCP 端口上。

**为什么要往多个地址各发一遍**：只发 `255.255.255.255` 时报文走默认路由，
而装了 VPN（Tailscale、Clash、公司隧道）的机器上默认路由往往指向隧道接口，
广播就出不了局域网。因此除有限广播外，还对每张本机网卡按 `/24` 推出的子网
广播地址（`192.168.1.255` 这样的地址命中直连路由）各发一次。
`/24` 是刻意的假设——`dart:io` 的 `NetworkInterface` 只给地址、不给子网掩码，
而家庭与办公室的局域网绝大多数就是 /24；假设不成立时还有有限广播兜底。

---

## 3. 三条链路的语义

### 3.1 搜索

```
向每个广播地址各发一份查询 → 收 timeout(3s) 内的单播应答 → 按 instanceId 去重
  → 按展示标签排序 → 截断到 10 台 → 剔除本机自己的会话
```

- **版本不一致的设备不计入可用列表**，但会单独计数：只有它、没有可用设备时，
  界面报的是「两台设备的版本不兼容」而不是「没搜到设备」。这两者的下一步
  完全不同（一个去升级，一个去查网络）。
- **本机自己的应答按 `instanceId` 剔除**：同一台设备既开着共享又点了搜索时
  会收到自己的回复。按「地址 + 端口」比对会漏掉多网卡与多网段的情况。

### 3.2 共享

```
读设置（设备名 / 端口）→ 生成配对码与 instanceId
  → HttpServer.bind(0.0.0.0, port)  +  RawDatagramSocket.bind(0.0.0.0, 8766)
  → 界面展示配对码
```

两个端口任一绑定失败都视为「启动失败」：只有 TCP 时对端根本找不到我们，
让用户看到「已开启共享」却永远搜不到，比直接报错更糟。

### 3.3 拉取

```
GET /handshake（验码，不传字节）
  → 快照本机的 lanSync 设置
  → GET /backup → 字节
  → decodeBackupUtf8
  → 按模式分支：
      合并 → BackupMergeService.merge（读本机 12 张表 → 纯函数合并 → 单事务替换）
      覆盖 → BackupImporter.import（单事务、12 张表全量替换）
  → 回写 lanSync 设置
  → 记录成功时间与对端标签
  → 界面失效全部读库缓存
```

- **两条模式共用同一个写事务**（`BackupImporter.replaceAll`），因此「合并」也
  天然是原子的：失败时本机一个字节都不变。
- **顺序不能调换**：先握手再取快照最后才下载——错码的代价应当是一次几百字节
  的请求，而不是一次 27MB 的传输。
- 覆盖模式与「从远端恢复（WebDAV）」是同一条导入路径，只是把交付方式从
  WebDAV 换成直连对端。

---

## 4. 失败模式与错误码

| 场景 | 错误码 | 可重试 | 用户看到 |
| --- | --- | --- | --- |
| 浏览器里使用 | `LAN_SYNC_UNSUPPORTED` | 否 | 请改用桌面端或移动端 |
| 广播出去没有任何应答 | `LAN_SYNC_HOST_NOT_FOUND` | 是 | 确认同网段且对方已开共享 |
| 只搜到版本不兼容的设备 | `LAN_SYNC_PROTOCOL_MISMATCH` | 否 | 把两台设备升级到同一版本 |
| 配对码错（401） | `LAN_SYNC_CODE_INVALID` | 是 | 核对主机上显示的 6 位数字 |
| 连续错码 ≥ 10 次 | `LAN_SYNC_CODE_LOCKED_OUT` | 否 | 共享已自动停止，请重新开启 |
| 端口被占用 | `LAN_SYNC_HOST_START_FAILED` | 是 | 换一个端口重试 |
| 连接被拒 / 超时 / 主机中途停共享 | `LAN_SYNC_UNREACHABLE` | 是 | 检查两台设备是否还在同一局域网 |
| 404（主机已停共享） | `LAN_SYNC_NOT_SHARING` | 否 | 对方已经停止共享 |
| 409（并发拉取） | `LAN_SYNC_BUSY` | 是 | 对方正在同步中 |
| 其它非 2xx | `LAN_SYNC_REQUEST_FAILED` | 5xx 为是 | 稍后重试 |
| 备份 > 100MB（413） | `BACKUP_TOO_LARGE` | 否 | 与本地导出同一句文案 |
| 非法 UTF-8 / JSON / 格式 | `BACKUP_INVALID_FORMAT` / `BACKUP_INVALID_JSON` | 否 | 与本地导入同一套文案 |
| 导入中途失败 | —（事务回滚） | — | 原数据不变，错误原样上抛 |

**发现失败不写状态行**：搜索是一次显式的、用户正在等的动作，结果直接显示在
当前界面；设置里的「上次失败」只描述**拉取**这条链路。

---

## 5. 五个刻意的取舍

### 5.1 单向：只有「主机 → 拉取方」，没有反向推送

服务端**没有写端点**。这是整个特性的核心安全属性：任何远端请求都不可能修改
本机数据；破坏性动作（覆盖）只发生在**拉取方本机**，且必须由本机用户敲
`RESTORE`。

"没有反向"曾经意味着"两台设备的进度不能相加"。**合并模式改变了这一点**：
合并是非破坏的并集，因此在反方向上再拉一次就能让两边都拿到全部数据
（见 §6.3 的两步配方）。主机仍然只读，安全属性一点没变。

### 5.2 主机只读，且共享必须每次显式开启

不做后台 / 定时 / 自动同步。应用退到后台或关闭即停止，配对码每次重新生成。
一个「一直开着」的共享端口等于把整库数据长期挂在局域网里。

### 5.3 配对码不落盘

配对码只活在主机的一次共享会话里（内存），因此它不会进备份、不会被导出的
JSON 带走——WebDAV 密码需要专门的导出剥离，这里根本不需要。

连续 10 次错码自动停共享：这是限流而不是锁定，重新开启会拿到一个新码，
合法用户能立刻恢复，而穷举者每次都要让受害者重新操作一次。

### 5.4 明文 HTTP，没有 TLS

局域网内明文传输。同网段的被动嗅探者能看到配对码与备份内容。
本版接受这个取舍（局域网通常是受信任的网络边界），代价写在 §6。

### 5.5 拉取后回写本机的 `lanSync` 设置

`BackupImporter.import` 会整份替换 `settings` 表，把主机的设备名与端口带过来。
若不回写，两台设备会变成同名设备（发现列表里再也分不清谁是谁），且本机端口
被改。因此拉取前取一份 `raw['lanSync']` 快照、导入后写回，且写回前先失效
`SettingsService` 的缓存（它是绕过缓存直接写库的，不失效就会用导入前的陈旧
快照做读-改-写基准）。

这条补丁只存在于局域网拉取路径，**不改变 WebDAV 恢复的既有语义**。

---

## 6. 合并模式

### 6.1 合并规则（逐表）

| 表 | 规则 | 冲突时 |
| --- | --- | --- |
| `words` | 唯一身份 `(normalized_term, source_language, target_language)` 相同的合成一行 | `updated_at` 更新的一侧赢；**但 `mastery_*` 永远不取对端**（它是派生值）；初始化状态保留本机值，新词不继承对端的 `QUEUED/RUNNING` 瞬态状态，因为任务队列是本机专属 |
| `word_contents` | 按映射后的 `word_id` 对齐 | `updated_at` 更新的一侧整行赢 |
| `review_logs` | 按 `client_answer_id` 取并集 | 同一条幂等键只留一份 |
| `study_sessions` | 身份 `(started_at, session_type, source_type)` 相同视为同一场 | 已存在则整场跳过（含题目） |
| `study_session_items` | 跟随它的会话整场插入 | 不逐题比对，避免 `(session, position)` 冲突 |
| `review_cards` / `wrong_word_states` / `words.mastery_*` | **只对「本次收到了新作答的词」重算** | 不做 LWW——它们必须彼此一致 |
| `word_review_stats` | 不出现在产物里 | 导入事务末尾按合并后的日志全量重算 |
| `settings` | 逐键取新 | 见 §6.2 |
| `import_batches` / `import_rows` / `initialization_jobs` / `provider_attempts` | **本机专属，原样带走** | 那是本机的操作历史与待办队列 |

**id 一定重编号**：八张表的自增主键在两台设备上必然撞车（各自从 1 开始）。
合并时按「身份」建立 `远端 id → 本机 id` 的映射，新插入的行取本机 `max(id)+1`，
子表（词典内容、卡片、错词、会话题目、作答流水）全部跟着改。

### 6.2 不参与合并的设置键

`lanSync`（设备名 / 端口）、`webdavBackup`（含密码）、`llmConfig`（API Key）、
`merriamWebsterDictionaryKey` / `merriamWebsterThesaurusKey`。

前两个是**本机属性**（搬过来会让两台设备同名、端口被改）；后三个是**凭据**。
合并是日常动作，不是换机动作——静默换掉对方的 API Key，用户只会在某天发现
"AI 不能用了"却找不到原因。其余设置（学习计划、题型、播放、词汇档位…）
跟着 `updated_at` 更新的一侧走。

### 6.3 两步配方：怎么做到「双向同步」

```
设备 B：搜索 A → 合并        # B 现在拥有 A ∪ B
设备 A：搜索 B → 合并        # A 也拥有 A ∪ B
```

第二遍时 B 已经把 A 的数据带上了，因此 A 拉到的就是完整的并集。
测试 `test/services/lan_sync/lan_sync_convergence_test.dart` 把这条性质钉住了：
两次合并之后两台的**词条集合、作答集合、每张卡片的 due/stability/difficulty
完全一致**（id 不必相同，那是各机自己的主键）。

### 6.4 派生状态为什么重放而不是取新

卡片、错词状态、熟练度都是 `review_logs` 的**函数**。如果对每张表各取
"更新时间更新的一份"，就会拼出「卡片来自 A、错词状态来自 B」这类自相矛盾的状态。
正确做法是把两份流水并起来按时间重走一遍：

```
for 每个「收到了新作答」的词:
    card  = 空卡
    wrong = 无
    for log in 合并后的日志（按 reviewed_at, client_answer_id 升序）:
        card  = scheduler.schedule(card, log.reviewed_at, log.rating)
        wrong = transitionWrongState(wrong, log.rating, log.is_correct, log.reviewed_at)
    mastery = calculateMasteryScore(card, wrong, 按日志算出的统计)
```

`test/services/merge/learning_replay_test.dart` 直接跑真实的复习流水线
（`ReviewService.processAnswer`），再把同一批日志拿去重放，逐字段对比——
重放与流水线只要有一处不一致就会红。

### 6.5 合并会改变什么

- **两边都复习过的词会重新排期**：重放用的是**本机**的目标保持率。两台设备
  保持率相同时结果与原值一致；不同时，这些词的到期日会按本机策略重排。
  这是刻意的（合并之后按本机策略走），但第一次合并时值得知道。
- **没收到新作答的词一行不动**：连带卡片行对象都不替换，避免"同步一次把整库
  到期日都刷一遍"。
- **未结束的会话也会被并进来**：它带着 PENDING 的题目，因此另一台设备的
  「继续上次学习」可能提示一场在你没碰过的机器上开始的会话。这是刻意的
  ——跨设备接着学是合理的。
- **改名会变成另一个身份**：`normalized_term` 变了就是新词条，两台设备会各留
  一条。这与 `words_identity_unique` 这条既有规则一致。

### 6.6 合并的内存代价

合并要把**本机 12 张表**与**对端的 12 张表**同时放进内存（导出器的导出路径
也是整库进内存）。真实备份约 27MB，解码后两份合计约 80–120MB 峰值。
低内存安卓机上词库特别大时可能吃力；界面在合并期间显示「处理中…」，
且中途失败会整事务回滚、本机不变。

---

## 7. 已知限制

1. **单向**：一次拉取只从一个方向搬。要两边一致，按 §6.3 各拉一次。
   覆盖模式仍然是破坏性的——它是给「这台设备的数据作废」这个场景留的。
2. **共享只在前台有效**：主机应用被系统冻结或切到后台后，端口可能被回收。
   没有前台服务，也不打算有——一个常驻的后台监听端口不值得。
3. **必须同一网段**：跨网段、跨 Vlan、跨 NAT 都搜不到（也没有手工填 IP 的入口）。
4. **明文传输**：见 §5.4。不要在不可信的 Wi-Fi 上开共享。
5. **无断点续传、无增量**：与本地导出、WebDAV 上传同一条全量路径
   （合并也是"传全量再合并"，好在对端不需要知道你要合并）。
6. **macOS 首次开启共享会弹防火墙授权**，必须允许，否则表现为
   `LAN_SYNC_HOST_START_FAILED`。
7. **macOS release 包需要 `com.apple.security.network.server`**：
   `DebugProfile.entitlements` 原本就有这一项（Flutter 热重载需要），
   因此**只在 debug 下测试会在 release 包上失败**。已在
   `macos/Runner/Release.entitlements` 显式声明。
8. **Android 明文 HTTP 未在真机验证**：客户端要连 `http://192.168.x.x:8765`。
   Android 9+ 默认禁止明文流量，而 `dart:io` 的 `HttpClient` 是否受
   `NetworkSecurityPolicy` 约束尚未实测。若真机上被拦
   （`CLEARTEXT communication not permitted`），需要在
   `android/app/src/main/res/xml/` 下加一份 network security config 并在
   manifest 上挂 `android:networkSecurityConfig`。这条对 WebDAV 同样适用，
   见 [`REMOTE_BACKUP.md`](REMOTE_BACKUP.md) §5.7。
9. **部分 Android ROM 的省电策略会限制 UDP 广播收包**，表现为「搜不到设备」。
   后续可以补一个手工填 `IP:端口` 的降级入口。
10. **Web 端不可用**：浏览器里既不能监听端口也不能发 UDP 广播，整个分组显示
    「请改用桌面端或移动端」。

---

## 8. 测试

全部离线，不碰真网络：

```bash
flutter test test/domain/models/lan_sync_settings_test.dart   # 解析容错/端口夹取/报文编解码
flutter test test/data/lan_sync/lan_sync_host_test.dart       # 真起 HttpServer：码错/413/409/错码限流/发现应答
flutter test test/data/lan_sync/lan_sync_discovery_test.dart  # 发现结果的纯函数 + 真实 UDP 往返
flutter test test/data/lan_sync/lan_sync_client_test.dart     # 请求构造 + 状态码映射
flutter test test/services/lan_sync/                          # 共享编排 + 拉取（真实内存库）
flutter test test/services/merge/                             # 重放 ≡ 流水线、统计 ≡ SQL、纯合并、集成与幂等
flutter test test/services/lan_sync/lan_sync_convergence_test.dart  # 两边各合并一次 → 完全一致
flutter test test/features/settings/lan_sync_section_test.dart # 四种界面状态与确认门
```

两层各负责一段：

- `test/data/lan_sync/lan_sync_host_test.dart` 与 `..._discovery_test.dart` **真的**
  绑 TCP / UDP 套接字（端口由系统分配，见 `test/support/free_udp_port.dart`），
  于是「我们真的按这套协议说话」是被断言的：路径、配对码请求头、响应头、
  401 / 404 / 405 / 409 / 413 各自的分支、错码限流、发现应答的单播。
- `test/support/fake_lan_sync_client.dart` 替换三个端口，于是共享编排与拉取
  的业务分支（先握手后下载、回写 lanSync、失败只写错误码、不动本地数据）
  不必伪造网络。
- `test/services/merge/` 是合并的核心：`learning_replay_test.dart` 拿真实流水线
  对拍重放，`word_stats_test.dart` 拿导入器的 SQL 对拍 Dart 统计，
  `backup_merge_test.dart` 逐条钉住合并规则，`backup_merge_service_test.dart`
  验证落库、幂等与失败回滚。

### 8.1 真机手测清单（改协议相关代码后请至少走一遍）

1. macOS 开共享 → 看到配对码与地址；用 `curl` 打一次 `/handshake`，
   对码应 200、错码应 401：
   ```bash
   curl -i -H 'LexiLoop-Sync-Code: <码>' http://<ip>:8765/lexiloop/v1/handshake
   ```
2. Android 搜索 → 命中 → 先故意输错一次（应看到「核对 6 位数字」）→ 输对 →
   **合并**确认 → 两台设备的词条都在；再切成**覆盖**重复一次 → 只剩主机的。
3. 拉取后**不重启应用**，首页 / 单词本 / 统计页显示新数据（缓存已失效）。
4. 拉取后本机的设备名与端口**没有**被主机的覆盖。
5. 关掉主机共享 → 客户端再拉 → 得到「对方已经停止共享」。
6. 在主机界面连续输错 10 次码（或抓包重放）→ 共享自动停止并显示提示；
   重新开启会拿到新码。
7. macOS 改成 release 构建再走一遍 1–2（验证 `network.server` 权限）。
8. Web 打开设置页 → 该分组显示不支持文案且不可操作。
9. 合并之后：本机原有的词条一条不少；统计页的「复习/正确」与「会话数/跳过数」
   都涨了；WebDAV 密码、AI Key、设备名、端口都没变。
10. A→B 合并一次、B→A 合并一次之后再各合一次 → 界面汇报「新增 0 个词条」，
    两台设备的词条数、作答数、卡片到期日一致。

---

## 9. 与「远程备份（WebDAV）」的关系

两者是同一件事的两种交付方式，刻意并存：

| | 局域网同步 | 远程备份（WebDAV） |
| --- | --- | --- |
| 是否需要第三方服务 | 不需要 | 需要一台 WebDAV |
| 适用场景 | 两台设备在同一个家/办公室 | 换机、异地、异地备份 |
| 方向 | 单向（主机 → 拉取方，各拉一次即同步） | 双向都能（上传 / 恢复都行） |
| 合并 | **支持**（保留双方进度） | 不支持，只有全量替换 |
| 自动执行 | 不能，每次显式开启 | 可以按周期自动上传 |
| 凭据 | 6 位配对码，不落盘 | 账号密码，落在设置表 |
| 传输 | 明文 HTTP | 取决于填的地址（建议 https） |

两者共用同一条导入路径（`BackupImporter`）与同一个导出器
（`BackupExporter`），因此「什么算一份完整备份」只有一处定义。
**合并目前只接在局域网同步上**——`BackupMergeService` 本身与传输无关，
将来把 WebDAV 的「从远端恢复」也加一个合并选项只是多一处装配。
