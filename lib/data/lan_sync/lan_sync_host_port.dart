/// 共享服务端的抽象端口（支持 v1 HTTP 拉取与 v2 WebSocket 双向增量会话）。
library;

import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_progress.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 一个正在运行的共享服务端。
abstract interface class LanSyncHost {
  /// 对端该连的根地址（`http://<本机 LAN IP>:<port>/`）。
  Uri get baseUri;

  /// 已经成功服务过多少次同步。
  int get servedCount;

  /// 停止服务并释放端口；可重复调用。
  Future<void> stop();
}

/// 客户端发起 v2 WebSocket 会话时发来的握手信息。
class LanSyncSessionHello {
  /// 以对端身份、同步模式与对端记忆的水位构造。
  const new({
    required this.deviceId,
    required this.deviceName,
    required this.deviceKind,
    required this.datasetEpoch,
    required this.mode,
    this.knownHostEpoch = '',
    this.pullSince,
  });

  /// 客户端持久化设备 ID。
  final String deviceId;

  /// 客户端展示设备名。
  final String deviceName;

  /// 客户端设备类型。
  final String deviceKind;

  /// 客户端当前数据集纪元。
  final String datasetEpoch;

  /// 客户端请求的同步模式。
  final LanSyncPullMode mode;

  /// 客户端上次同步时记住的主机数据集纪元。
  final String knownHostEpoch;

  /// 客户端上次从主机拉取时记住的主机水位时钟。
  final int? pullSince;
}

/// 主机对 v2 会话握手的协商回应。
class LanSyncSessionHelloReply {
  /// 以协商后的模式、主客端水位与主机身份构造。
  const new({
    required this.acceptedMode,
    required this.hostEndpoint,
    required this.hostIdentity,
    this.effectivePullSince,
    this.pushSince,
  });

  /// 最终确认的同步模式。
  final LanSyncPullMode acceptedMode;

  /// 主机端展示信息。
  final LanSyncEndpoint hostEndpoint;

  /// 主机端持久化身份与纪元。
  final LanSyncIdentity hostIdentity;

  /// 本次主机发给客户端的有效增量起始水位；`null` 表示发精简全量。
  final int? effectivePullSince;

  /// 本次请求客户端推给主机的增量起始水位；`null` 表示客户端推精简全量。
  final int? pushSince;
}

/// 主机落库客户端增量后的结果。
class LanSyncHostApplyResult {
  /// 以合并摘要与主机最新纪元构造。
  const new({required this.summary, required this.datasetEpoch});

  /// 主机侧本次新增/更新统计。
  final LanSyncDeltaSummary summary;

  /// 落库后的主机数据集纪元（供通知当前对端更新记忆）。
  final String datasetEpoch;
}

/// 主机端 v2 WebSocket 双向增量会话的业务委托。
///
/// 保持分层清晰：数据层只管 WebSocket 帧与分片传输，数据库读写、水位管理
/// 与界面进度发布全部经由该接口委托给服务层。
abstract interface class LanSyncSessionDelegate {
  /// 校验共享策略并协商本次双侧水位线。
  Future<LanSyncSessionHelloReply> negotiateSession(LanSyncSessionHello hello);

  /// 导出并发出主机端压缩载荷（增量或全量）。
  Future<LanSyncWirePayload> exportForSession({
    required LanSyncPullMode mode,
    required int? since,
  });

  /// 将客户端上传的压缩增量合入主机数据库。
  Future<LanSyncHostApplyResult> applyIncomingDelta({
    required Uint8List compressedBytes,
    required LanSyncSessionHello peer,
    required int localServerNow,
  });

  /// 单向拉取完成后记录对端水位（不改主机数据）。
  Future<void> recordOneWayServed({
    required LanSyncSessionHello peer,
    required int localServerNow,
  });

  /// 实时上报主机侧同步进度以驱动「双端词环共振桥」动画。
  void onSessionProgress(LanSyncTransferProgress progress);
}

/// 启动共享服务端所需的全部参数。
class LanSyncHostOptions {
  /// 以核心配置与回调构造。
  const new({
    required this.deviceName,
    required this.port,
    required this.pairingCode,
    required this.instanceId,
    required this.backupSource,
    required this.onCodeLockout,
    required this.onServed,
    this.discoveryPort = lanSyncDiscoveryPort,
    this.deviceId = '',
    this.deviceKind = '',
    this.datasetEpoch = '',
    this.allowsBidirectional = true,
    this.sessionDelegate,
  });

  /// 本机展示名。
  final String deviceName;

  /// 监听的 TCP 端口。
  final int port;

  /// 本次会话的配对码。
  final String pairingCode;

  /// 本次共享会话的随机标识。
  final String instanceId;

  /// 应答发现查询的 UDP 端口。
  final int discoveryPort;

  /// 本机持久化设备 ID。
  final String deviceId;

  /// 本机设备类型（桌面 / 手机）。
  final String deviceKind;

  /// 本机数据集纪元。
  final String datasetEpoch;

  /// 当前是否允许一键双向增量合并。
  final bool allowsBidirectional;

  /// 按需产出全量备份（供 v1 HTTP 拉取使用）。
  final LanSyncBackupSource backupSource;

  /// 可选的 v2 WebSocket 会话委托；为空时只提供 v1 HTTP 能力。
  final LanSyncSessionDelegate? sessionDelegate;

  /// 成功服务完一次同步时回调，参数是累计次数。
  final void Function(int servedCount) onServed;

  /// 配对码连续错误到达上限时回调。
  final void Function() onCodeLockout;
}

/// 启动一个共享服务端。
typedef LanSyncHostStarter = Future<LanSyncHost> Function(
  LanSyncHostOptions options,
);
