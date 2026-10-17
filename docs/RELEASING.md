# 发布构建（Android / macOS）

本文记录 LexiLoop 的固定签名、GitHub Actions 手动发布流程，以及两个平台产物的
分发限制。应用本身仍然**不依赖自建服务端**；CI 只注入构建所需的签名材料，不注入
任何 AI / 词典密钥。

## 1. 固定 Android 签名

发布签名材料放在本机，**不进 git**：

| 文件 | 内容 | 是否提交 |
|---|---|---|
| `android/app/lexiloop-release.jks` | PKCS12 格式的 RSA 4096 发布密钥，别名 `lexiloop` | 否（`/android/app/*.jks` 已忽略） |
| `android/key.properties` | `storePassword` / `keyPassword` / `keyAlias` / `storeFile` | 否（`/android/key.properties` 已忽略） |
| `android/key.properties.example` | 只含占位符的模板 | 是 |

`android/app/build.gradle.kts` 会在 `android/key.properties` 存在时使用
`release` 签名；不存在时回退 debug 签名并打 warning，保证普通
`flutter run --release` 仍可用。**可分发 APK 的签名正确性由 CI 的证书比对保证**，
所以不要跳过 workflow 里的 `Verify signer`。

### 备份（重要）

GitHub Secrets 只能写入、不能读回。**本机这两个文件是唯一可恢复副本**：

- 把 `android/app/lexiloop-release.jks` 和 `android/key.properties`
  复制到密码管理器 / 加密磁盘。
- 不要重新生成密钥来“修复”问题；换 key 会让已安装的旧版本无法覆盖升级。
- 密钥丢失后只能生成新 key，用户必须卸载旧版本再安装（本地数据需先导出备份）。

### 旧安装升级

当前旧包是 **debug 签名**。第一次安装 fixed-key release 包时，
`adb install -r` 会因签名不一致失败：

1. 在应用内「设置 → 数据管理」导出一份备份到设备外。
2. 卸载旧包（`adb uninstall com.lexiloop.lexiloop`）。
3. 安装新 APK。
4. 重新导入备份。

## 2. GitHub Secrets

仓库：`lengsukq/LexiLoop`。在仓库根目录执行（值从本机文件读取，不打印）：

```bash
gh secret set ANDROID_KEYSTORE_PASSWORD < <(sed -n 's/^storePassword=//p' android/key.properties)
gh secret set ANDROID_KEY_PASSWORD < <(sed -n 's/^keyPassword=//p' android/key.properties)
gh secret set ANDROID_KEY_ALIAS < <(printf '%s' lexiloop)
gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 < android/app/lexiloop-release.jks)
gh secret list
```

CI 在 `ubuntu-latest` 上把 base64 还原成 `android/app/lexiloop-release.jks`，
再按 secrets 写出 `android/key.properties`，最后用 `keytool` 与 `apksigner`
比对证书 SHA-256。四个值缺一不可。

## 3. 版本与手动触发

### 版本号规则

- `pubspec.yaml` 只维护 0.x 基础版本，当前 `0.1.0+1`；CI 取 `major.minor` = `0.1`。
- 每次构建由 `prepare` job 生成：
  - `version_name = 0.1.<Asia/Shanghai 时间戳 yyyyMMddHHmmss>`，例如
    `0.1.20261017231818`；
  - `build_number = Unix 秒`，作为 Android `versionCode` / macOS
    `CFBundleVersion`。
- 时间戳版本天然递增；`build_number` 仍在 Android 2,100,000,000 上限内
  （约 2036 年前）。
- GitHub Release 的 tag 为 `v<version_name>`，例如 `v0.1.20261017231818`。

workflow 文件在**默认分支 `main`**：

```text
.github/workflows/release.yml
```

原因：GitHub 的「Run workflow」按钮只认默认分支上的 `workflow_dispatch`
workflow。Flutter 应用在 `flutter` 分支，所以 workflow 放在 `main`，构建时
`actions/checkout` 到 `source_ref`（默认 `flutter`）解析出的**具体 commit SHA**；
构建、签名和 Release tag 都指向同一个 SHA。

### 网页

1. 打开 Actions → **Build Release (Android / macOS)**。
2. 点 **Run workflow**，分支保持 **main**（不要切到 flutter，workflow 文件不在那里）。
3. 选择：
   - `platform`: `all` / `android` / `macos`
   - `source_ref`: 默认 `flutter`
4. Run。

### 命令行

```bash
gh workflow run release.yml \
  --ref main \
  -f platform=all \
  -f source_ref=flutter

gh run list --workflow release.yml --limit 3
gh run watch <run-id> --exit-status
```

版本号不再由手输入；每次运行自动生成。需要固定版本时，先改
`pubspec.yaml` 的 `major.minor`（例如 `0.2.0+1`），CI 会从 `0.2` 继续拼时间戳。

## 4. 产物与 GitHub Release

每次成功运行会创建一个 GitHub Release（tag `v<version_name>`），APK / zip 同时作为
Release asset 和 Actions artifact 上传：

| 平台 | 文件 | 说明 |
|---|---|---|
| Android | `LexiLoop-<version_name>-<build_number>-android.apk` | 通用 APK（包含全部 ABI） |
| macOS | `LexiLoop-<version_name>-<build_number>-macos-<archs>.zip` | 内含 `lexiloop.app`；`archs` 来自 `lipo -archs`，当前 Release 构建为 `x86_64-arm64`（universal） |

- Release 只在所选平台的 job 全部成功时创建；任一 job 失败/取消都不会发布半成品。
- `platform=android` 或 `macos` 时只附带该平台产物。
- Actions artifact 保留 90 天；Release asset 长期保留，建议从 Releases 页面下载。
- Release notes 会写明 build number、source ref/SHA 和两个平台的安装提示。

### macOS 首次启动

macOS 产物是 **ad-hoc 签名、未公证**。从浏览器下载后系统会加 quarantine：

- 右键 App →「打开」→ 再点「打开」；或
- `xattr -dr com.apple.quarantine /Applications/lexiloop.app`

zip 请用 Finder「归档实用工具」或 `ditto -x -k` 解压，避免普通解压工具破坏
签名/扩展属性。当前 Release 构建是 **universal binary（x86_64 + arm64）**，
Intel Mac 与 Apple Silicon 都能原生运行；zip 名里的架构组合由 `lipo -archs`
实际读出，不是 runner 的 `uname -m`。

## 5. 本地构建

```bash
flutter pub get

# Android release（需要 android/key.properties）
flutter build apk --release

# macOS release（本机 ad-hoc 签名）
flutter build macos --release
```

产物：

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/macos/Build/Products/Release/lexiloop.app`

本地构建使用 `pubspec.yaml` 的 `0.1.0+1`，不会自动加 CI 时间戳；需要与 CI 一致时
手动传 `--build-name` / `--build-number`。CI 的 `versionCode` 是 epoch 秒，远大于
本地 `1`，覆盖安装没问题，但系统不允许降级安装。

验签：

```bash
"$ANDROID_HOME/build-tools/36.0.0/apksigner" verify --print-certs \
  build/app/outputs/flutter-apk/app-release.apk
codesign --verify --deep --strict \
  build/macos/Build/Products/Release/lexiloop.app
```

## 6. CI 的边界

- **只构建已提交代码**：workflow checkout `flutter` 的 HEAD；本地未提交改动不会
  进入 CI 产物。要让 CI 包含当前工作区，先提交并推送（或另建临时分支）。
- **不跑全量测试**：本 workflow 只做 release 构建、签名校验与发布；提交前门禁仍按
  README 的 `dart format` / `dart analyze` / `flutter test` 执行。
- **Release 是原子的**：只有所选平台的 job 全部成功才创建 GitHub Release；部分
  失败时只保留 Actions artifact，不会发出缺平台的 release。
- **私有仓库分钟数**：macOS runner 按 10 倍计费；日常只验 Android 时把
  `platform` 选 `android`。
- **Flutter 版本固定**：workflow 使用 `3.47.5`，与本机 `.metadata` 对齐。升级
  Flutter 时同时更新 workflow 和本文件。
- **默认分支**：如果以后把默认分支改成 `flutter`，需要把
  `.github/workflows/release.yml` 同步到新默认分支，否则「Run workflow」按钮
  会消失。
- **时间戳时区**：`version_name` 用 Asia/Shanghai；`build_number` 是 Unix 秒，
  与显示时区无关。

## 7. 轮换 / 故障处理

- **证书不匹配**：先看 CI 的 `Restore signing material` 是否通过；再对比
  `keytool -list -v` 与 `apksigner verify --print-certs` 的 SHA-256。Secret 被
  覆盖或 keystore 被替换都会导致失败。
- **macOS 未签名 / 签名损坏**：`codesign --verify` 失败时不要直接分发；先检查
  Xcode 构建日志里的 `CODE_SIGN_IDENTITY`，本仓库 Release 配置应为 `-`
  （ad-hoc）。
- **换 key**：生成新 keystore → 更新本机 `key.properties` → 重新上传四个
  Secrets → 重新构建。已安装用户必须卸载重装。
- **Release tag 冲突**：同一秒内触发两次会得到相同 `v<version_name>`；等几秒
  重跑，或删除冲突的 tag/Release 后重试。
- **Release 发布失败**：检查 `Publish GitHub Release` job；它需要
  `contents: write`（workflow 已声明），并确认 `gh release create` 的 tag 尚不存在。
