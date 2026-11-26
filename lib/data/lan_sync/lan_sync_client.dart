/// 拉取对端备份的抽象端口。
///
/// 与 `RemoteBackupClient` 同一套约定：业务层（发现 → 握手 → 下载 → 导入）
/// 只依赖这两个方法，协议细节由 `lan_sync_client_dio.dart` 单独钉住，
/// 测试里一个内存实现就能覆盖全部分支。
library;

import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 一台对端设备的只读客户端。
///
/// 失败一律抛业务错误（`lib/core/errors.dart` 的 `AppError`），由调用方决定文案。
abstract interface class LanSyncClient {
  /// 验一次配对码并取回对端信息。
  ///
  /// 必须在 [downloadBackup] 之前调用：错码的代价应当是一次几百字节的请求，
  /// 而不是一次完整备份的传输。
  Future<LanSyncHandshake> handshake();

  /// 下载对端的整份备份。
  ///
  /// 超过 `maxBackupBytes` 时必须拒绝，而不是把整个响应读进内存。
  Future<LanSyncBackup> downloadBackup();
}

/// 按「目标设备 + 配对码」构造客户端。
///
/// **为什么传工厂而不是客户端实例**：配对码由用户每次输入，目标设备由每次
/// 搜索决定。让服务每次现造客户端，就不存在「握着上一次的码」这种状态。
typedef LanSyncClientFactory = LanSyncClient Function(
  DiscoveredLanHost host,
  String pairingCode,
);
