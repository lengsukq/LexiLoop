/// 局域网同步的 HTTP（v1 兼容）与 WebSocket（v2 双向增量）线上契约。
///
/// 路径、请求头、握手字段与 WebSocket 控制帧类型统一收在此处，服务端与客户端
/// 共用同一份定义，避免字段名漂移；数值常量集中在 `lib/core/constants.dart`。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';

/// 握手路径：只验配对码与协商能力，不传数据字节。
const String lanSyncHandshakePath = '/lexiloop/v1/handshake';

/// 全量备份下载路径（支持 `Accept-Encoding: gzip`）。
const String lanSyncBackupPath = '/lexiloop/v1/backup';

/// v2 双向增量与双端实时进度 WebSocket 会话路径。
const String lanSyncSessionPath = '/lexiloop/v2/session';

/// 配对码所在的请求头。
const String lanSyncCodeHeader = 'LexiLoop-Sync-Code';

/// 响应头：备份文件名（与本地导出的命名逐字一致）。
const String lanSyncBackupNameHeader = 'X-LexiLoop-Backup-Name';

/// 响应头：备份总行数。
const String lanSyncBackupRowsHeader = 'X-LexiLoop-Backup-Rows';

/// 握手响应里的字段名。
const String lanSyncHandshakeServiceField = 'service';

/// 握手响应里的协议版本字段名。
const String lanSyncHandshakeVersionField = 'version';

/// 握手响应里的设备名字段名。
const String lanSyncHandshakeDeviceField = 'device';

/// 握手响应里的持久化设备 ID 字段名。
const String lanSyncHandshakeDeviceIdField = 'deviceId';

/// 握手响应里的设备类型字段名。
const String lanSyncHandshakeDeviceKindField = 'deviceKind';

/// 握手响应里的是否允许双向合并字段名。
const String lanSyncHandshakeBidirectionalField = 'allowsBidirectional';

/// 握手响应里的数据集纪元字段名。
const String lanSyncHandshakeEpochField = 'datasetEpoch';

/// 错误响应里的错误码字段名。
const String lanSyncErrorCodeField = 'error';

/// WebSocket 控制帧类型常量。
abstract final class LanSyncWsType {
  /// 客户端首包：身份、模式与已知主机水位。
  static const String hello = 'hello';

  /// 服务端协商回应：确认模式、本机身份与客户端应推水位。
  static const String helloAck = 'hello_ack';

  /// 主机即将下发数据载荷的元信息。
  static const String pullMeta = 'pull_meta';

  /// 主机数据载荷发送完毕。
  static const String pullEnd = 'pull_end';

  /// 客户端即将上传增量载荷的元信息（仅双向模式）。
  static const String pushMeta = 'push_meta';

  /// 客户端增量载荷发送完毕。
  static const String pushEnd = 'push_end';

  /// 阶段状态同步（如通知对端「正在合并」）。
  static const String stage = 'stage';

  /// 客户端落库完成并汇报本侧摘要。
  static const String clientDone = 'client_done';

  /// 主机落库完成并汇报本侧摘要。
  static const String hostDone = 'host_done';

  /// 业务或协议错误。
  static const String error = 'error';
}

/// 一次成功握手的对端信息。
class LanSyncHandshake {
  /// 以设备名、协议版本及可选 v2 能力字段构造。
  const new({
    required this.deviceName,
    required this.protocolVersion,
    this.deviceId = '',
    this.deviceKind = '',
    this.allowsBidirectional = true,
    this.datasetEpoch = '',
  });

  /// 对端展示的设备名；缺失时为空串。
  final String deviceName;

  /// 对端的协议版本。
  final int protocolVersion;

  /// 对端持久化设备 ID（v1 对端为空串）。
  final String deviceId;

  /// 对端设备类型（桌面 / 手机）。
  final String deviceKind;

  /// 对端是否允许一键双向增量合并。
  final bool allowsBidirectional;

  /// 对端当前的数据集纪元。
  final String datasetEpoch;

  /// 编码成响应体。
  String toJsonBody() => jsonEncode(<String, Object?>{
    lanSyncHandshakeServiceField: lanSyncServiceName,
    lanSyncHandshakeVersionField: protocolVersion,
    lanSyncHandshakeDeviceField: deviceName,
    if (deviceId.isNotEmpty) lanSyncHandshakeDeviceIdField: deviceId,
    if (deviceKind.isNotEmpty) lanSyncHandshakeDeviceKindField: deviceKind,
    lanSyncHandshakeBidirectionalField: allowsBidirectional,
    if (datasetEpoch.isNotEmpty) lanSyncHandshakeEpochField: datasetEpoch,
  });
}

/// 解析握手响应体；服务标识不符时返回 `null`。
LanSyncHandshake? parseLanSyncHandshake(String body) {
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  if (decoded[lanSyncHandshakeServiceField] != lanSyncServiceName) return null;

  final version = decoded[lanSyncHandshakeVersionField];
  if (version is! num) return null;
  final device = decoded[lanSyncHandshakeDeviceField];
  final deviceId = decoded[lanSyncHandshakeDeviceIdField];
  final deviceKind = decoded[lanSyncHandshakeDeviceKindField];
  final bidirectional = decoded[lanSyncHandshakeBidirectionalField];
  final epoch = decoded[lanSyncHandshakeEpochField];

  return LanSyncHandshake(
    deviceName: device is String ? device.trim() : '',
    protocolVersion: version.round(),
    deviceId: deviceId is String ? deviceId.trim() : '',
    deviceKind: deviceKind is String ? deviceKind.trim() : '',
    allowsBidirectional: bidirectional is! bool || bidirectional,
    datasetEpoch: epoch is String ? epoch.trim() : '',
  );
}

/// 一次失败响应的响应体。
String lanSyncErrorBody(String code) =>
    jsonEncode(<String, Object?>{lanSyncErrorCodeField: code});

/// 通过 WebSocket 传输的一份已压缩载荷及其元信息。
class LanSyncWirePayload {
  /// 以压缩字节与元信息构造。
  const new({
    required this.compressedBytes,
    required this.uncompressedBytes,
    required this.totalRows,
    required this.isIncremental,
    required this.serverNow,
    this.datasetEpoch = '',
  });

  /// GZip 压缩后的传输字节。
  final Uint8List compressedBytes;

  /// 压缩前的原始 JSON UTF-8 字节数。
  final int uncompressedBytes;

  /// 包含的记录行数。
  final int totalRows;

  /// 是否增量载荷。
  final bool isIncremental;

  /// 导出端快照时钟。
  final int serverNow;

  /// 导出端数据集纪元。
  final String datasetEpoch;

  /// 编码为 `pull_meta` / `push_meta` 控制帧。
  Map<String, Object?> toMetaFrame(String type) => <String, Object?>{
    'type': type,
    'totalBytes': compressedBytes.length,
    'uncompressedBytes': uncompressedBytes,
    'totalRows': totalRows,
    'isIncremental': isIncremental,
    'serverNow': serverNow,
    'datasetEpoch': datasetEpoch,
  };
}
