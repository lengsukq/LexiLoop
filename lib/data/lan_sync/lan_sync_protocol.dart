/// 局域网同步的 HTTP 线上契约。
///
/// **为什么线上字符串跟着解析器走**：与 `backupFormat` 之于
/// `backup_import.dart` 同理——路径、请求头名、握手字段名同时被服务端写、
/// 被客户端读，放在同一个文件里改一处就不会漂移；而**数值**（端口、超时、
/// 状态码边界）按仓库约定集中在 `lib/core/constants.dart`。
///
/// 完整协议见 `docs/LAN_SYNC.md` §3。
library;

import 'dart:convert';

import 'package:lexiloop/core/constants.dart';

/// 握手路径：只验配对码，不传字节。
///
/// **为什么必须有这一步**：直接拉备份的话，一次错码的代价是让主机导出并
/// 传出一份 27MB 的数据；先握手能把「码对不对」与「传不传数据」分开。
const String lanSyncHandshakePath = '/lexiloop/v1/handshake';

/// 备份下载路径。
const String lanSyncBackupPath = '/lexiloop/v1/backup';

/// 配对码所在的请求头。
///
/// 用自定义头而不是查询串：查询串会被写进任何中间层的访问日志，
/// 而配对码是一道门禁。
const String lanSyncCodeHeader = 'LexiLoop-Sync-Code';

/// 响应头：备份文件名（与本地导出的命名逐字一致）。
const String lanSyncBackupNameHeader = 'X-LexiLoop-Backup-Name';

/// 响应头：备份总行数。
///
/// 握手不导出数据，因此「对方有多少条词」这个信息只能在下载响应里带上。
const String lanSyncBackupRowsHeader = 'X-LexiLoop-Backup-Rows';

/// 握手响应里的字段名。
const String lanSyncHandshakeServiceField = 'service';

/// 握手响应里的协议版本字段名。
const String lanSyncHandshakeVersionField = 'version';

/// 握手响应里的设备名字段名。
const String lanSyncHandshakeDeviceField = 'device';

/// 错误响应里的错误码字段名。
const String lanSyncErrorCodeField = 'error';

/// 一次成功握手的对端信息。
class LanSyncHandshake {
  /// 以设备名与协议版本构造。
  const new({required this.deviceName, required this.protocolVersion});

  /// 对端展示的设备名；缺失时为空串。
  final String deviceName;

  /// 对端的协议版本。
  final int protocolVersion;

  /// 编码成响应体。
  String toJsonBody() => jsonEncode(<String, Object?>{
    lanSyncHandshakeServiceField: lanSyncServiceName,
    lanSyncHandshakeVersionField: protocolVersion,
    lanSyncHandshakeDeviceField: deviceName,
  });
}

/// 解析握手响应体。
///
/// **服务标识不符时返回 `null` 而不是抛异常**：这不是「协议不兼容」，
/// 而是「对方根本不是 LexiLoop」（地址被别的程序占了）。两者对用户的含义
/// 完全不同，调用方要据此给出不同文案。
///
/// 协议版本**不在这里拒绝**：调用方要报的是「版本不兼容」，
/// 那需要知道版本号本身。
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

  return LanSyncHandshake(
    deviceName: device is String ? device.trim() : '',
    protocolVersion: version.round(),
  );
}

/// 一次失败响应的响应体。
///
/// 客户端只按状态码分支，因此这个体的用途是**排错**：抓包或日志里能直接
/// 看到是「码错」还是「忙」，而不必去猜 401 与 409 各是什么语义。
String lanSyncErrorBody(String code) =>
    jsonEncode(<String, Object?>{lanSyncErrorCodeField: code});
