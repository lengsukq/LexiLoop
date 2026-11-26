/// 局域网同步的设置模型、水位线记录与发现报文模型。
///
/// **配对码刻意不在这个模型里**：它只活在主机的一次共享会话中（内存），
/// 不会落盘，也不会随备份文件外流。
///
/// **为什么引入持久化 `deviceId`、`datasetEpoch` 与 `peerWatermarks`**：
/// 增量同步需要记住「上次和这台设备同步时，对方数据走到哪个时间戳」。
/// - `deviceId` 跨共享会话不变（`instanceId` 每次开启共享都换，只用于自过滤）；
/// - `datasetEpoch` 在清空数据或覆盖恢复后轮换，保证对端自动回退到全量合并；
/// - `peerWatermarks` 按对端 `deviceId` 记录双侧水位，最多保留
///   [lanSyncMaxTrackedPeers] 台最近同步过的设备。
///
/// 本文件必须保持纯 Dart（`lib/domain` 的守卫会检查）。
library;

import 'package:lexiloop/core/constants.dart';

/// 局域网同步设置在键值表里的键名。
const String lanSyncSettingsKey = 'lanSync';

/// 设备名的兜底值。
const String lexiloopDeviceNameDefault = 'LexiLoop';

/// 按平台推导默认设备名。
String defaultLanSyncDeviceName({required bool isDesktop}) => isDesktop
    ? '$lexiloopDeviceNameDefault 桌面'
    : '$lexiloopDeviceNameDefault 手机';

/// 按平台推导设备类型标识。
String lanSyncDeviceKind({required bool isDesktop}) =>
    isDesktop ? lanSyncDeviceKindDesktop : lanSyncDeviceKindMobile;

/// 主机开启共享时的安全策略。
enum LanSyncSharePolicy {
  /// 允许一键双向增量合并（只增不删，绝不开放覆盖/删除端点）。
  bidirectional('BIDIRECTIONAL'),

  /// 严格只读：只允许对端拉取数据，拒绝写入本机。
  readOnly('READ_ONLY');

  new(this.wire);

  /// 存储标识。
  final String wire;

  /// 按存储标识反查；未知值回落到 [bidirectional]。
  static LanSyncSharePolicy fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return LanSyncSharePolicy.bidirectional;
  }
}

/// 从对端同步数据的方式。
enum LanSyncPullMode {
  /// 一次配对完成双向增量合并：双方都拿到全部新词条与作答，一条不删。
  bidirectional('BIDIRECTIONAL'),

  /// 单向拉取合并：只把对方数据并进本机，本机现有数据一条不删。
  merge('MERGE'),

  /// 用对端的完整备份整体替换本机。
  replace('REPLACE');

  new(this.wire);

  /// 存储标识。
  final String wire;

  /// 按存储标识反查；未知值回落到 [merge]（非破坏性，安全兜底）。
  static LanSyncPullMode fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return LanSyncPullMode.merge;
  }
}

/// 与某台对端设备之间的增量同步水位线。
class LanSyncPeerWatermark {
  /// 以对端设备标识、纪元与双侧游标构造。
  const new({
    required this.peerDeviceId,
    required this.peerDatasetEpoch,
    required this.peerCursorMs,
    this.localCursorMs = 0,
    this.lastSyncedAt = 0,
  });

  /// 对端持久化设备 ID。
  final String peerDeviceId;

  /// 上次同步时对端的数据集纪元；若对端纪元变更则水位失效、自动全量同步。
  final String peerDatasetEpoch;

  /// 上次拉取时对端主机的导出时钟（下次拉取以此为 `since`）。
  final int peerCursorMs;

  /// 上次推送给对端时本机的导出时钟（下次推送以此为 `since`）。
  final int localCursorMs;

  /// 本机记录的最近同步时间戳（用于 LRU 淘汰超出上限的旧记录）。
  final int lastSyncedAt;

  /// 写回存储映射。
  Map<String, Object?> toStorage() => <String, Object?>{
    'peerDeviceId': peerDeviceId,
    'peerDatasetEpoch': peerDatasetEpoch,
    'peerCursorMs': peerCursorMs,
    'localCursorMs': localCursorMs,
    'lastSyncedAt': lastSyncedAt,
  };

  /// 从存储映射解析；缺失核心标识时返回 `null`。
  static LanSyncPeerWatermark? fromRaw(Object? raw) {
    if (raw is! Map) return null;
    final id = _nonEmptyString(raw['peerDeviceId']);
    if (id == null) return null;
    return LanSyncPeerWatermark(
      peerDeviceId: id,
      peerDatasetEpoch: _string(raw['peerDatasetEpoch']).trim(),
      peerCursorMs: _nonNegativeInt(raw['peerCursorMs']),
      localCursorMs: _nonNegativeInt(raw['localCursorMs']),
      lastSyncedAt: _nonNegativeInt(raw['lastSyncedAt']),
    );
  }
}

/// 局域网同步的本机配置、持久化身份与同步状态。
class LanSyncSettings {
  /// 以基础配置构造；可选字段通过 [copyWith] 或 [lanSyncSettingsFromRaw] 填充。
  const new({
    required this.deviceName,
    required this.port,
    this.pullMode = LanSyncPullMode.merge,
    this.sharePolicy = LanSyncSharePolicy.bidirectional,
    this.identity = const LanSyncIdentity(),
    this.status = const LanSyncLastStatus(),
    this.peerWatermarks = const <String, LanSyncPeerWatermark>{},
  });

  /// 未配置任何内容时的默认值。
  static const LanSyncSettings defaults = LanSyncSettings(
    deviceName: '',
    port: lanSyncDefaultPort,
  );

  /// 本机在发现列表里的展示名；空串表示使用平台推导的兜底名。
  final String deviceName;

  /// 共享服务端监听的 TCP 端口。
  final int port;

  /// 拉取/同步方式（默认保留兼容 [LanSyncPullMode.merge]）。
  final LanSyncPullMode pullMode;

  /// 本机开启共享时的安全策略（默认允许双向增量合并）。
  final LanSyncSharePolicy sharePolicy;

  /// 持久化设备身份与数据集纪元。
  final LanSyncIdentity identity;

  /// 上次同步状态快照。
  final LanSyncLastStatus status;

  /// 按对端 `deviceId` 索引的增量同步水位线。
  final Map<String, LanSyncPeerWatermark> peerWatermarks;

  /// 上次成功同步时间戳（便捷访问）。
  int? get lastSuccessAt => status.lastSuccessAt;

  /// 上次失败错误码（便捷访问）。
  String? get lastError => status.lastError;

  /// 上次同步的对端标签（便捷访问）。
  String? get lastPeer => status.lastPeer;

  /// 持久化设备 ID（空串表示尚未初始化）。
  String get deviceId => identity.deviceId;

  /// 数据集纪元（空串表示尚未初始化）。
  String get datasetEpoch => identity.datasetEpoch;

  /// 展示名：用户填了就用它，否则用平台兜底名。
  String effectiveDeviceName({required String fallback}) =>
      deviceName.isEmpty ? fallback : deviceName;

  /// 覆盖若干字段，其余原样保留。
  LanSyncSettings copyWith({
    String? deviceName,
    int? port,
    LanSyncPullMode? pullMode,
    LanSyncSharePolicy? sharePolicy,
    LanSyncIdentity? identity,
    int? lastSuccessAt,
    String? lastError,
    String? lastPeer,
    bool clearError = false,
    bool clearPeer = false,
    Map<String, LanSyncPeerWatermark>? peerWatermarks,
  }) => LanSyncSettings(
    deviceName: deviceName ?? this.deviceName,
    port: port ?? this.port,
    pullMode: pullMode ?? this.pullMode,
    sharePolicy: sharePolicy ?? this.sharePolicy,
    identity: identity ?? this.identity,
    status: LanSyncLastStatus(
      lastSuccessAt: lastSuccessAt ?? status.lastSuccessAt,
      lastError: clearError ? null : (lastError ?? status.lastError),
      lastPeer: clearPeer ? null : (lastPeer ?? status.lastPeer),
    ),
    peerWatermarks: peerWatermarks ?? this.peerWatermarks,
  );

  /// 写回 `settings.raw[lanSyncSettingsKey]` 的形态。
  Map<String, Object?> toStorage() => <String, Object?>{
    if (deviceName.isNotEmpty) 'deviceName': deviceName,
    'port': port,
    'pullMode': pullMode.wire,
    'sharePolicy': sharePolicy.wire,
    if (identity.deviceId.isNotEmpty) 'deviceId': identity.deviceId,
    if (identity.datasetEpoch.isNotEmpty) 'datasetEpoch': identity.datasetEpoch,
    if (status.lastSuccessAt != null) 'lastSuccessAt': status.lastSuccessAt,
    if (status.lastError != null) 'lastError': status.lastError,
    if (status.lastPeer != null) 'lastPeer': status.lastPeer,
    if (peerWatermarks.isNotEmpty)
      'peerWatermarks': <String, Object?>{
        for (final entry in _cappedWatermarks(peerWatermarks).entries)
          entry.key: entry.value.toStorage(),
      },
  };
}

/// 持久化设备身份与数据集纪元（从 [LanSyncSettings] 拆出以保持构造精简）。
class LanSyncIdentity {
  /// 以设备 ID 与数据集纪元构造。
  const new({this.deviceId = '', this.datasetEpoch = ''});

  /// 跨共享会话稳定的设备 ID。
  final String deviceId;

  /// 数据集纪元（清空或覆盖后轮换）。
  final String datasetEpoch;

  /// 是否已初始化。
  bool get isReady => deviceId.isNotEmpty && datasetEpoch.isNotEmpty;
}

/// 上次同步的成败与对端快照。
class LanSyncLastStatus {
  /// 以时间、错误码与对端标签构造。
  const new({this.lastSuccessAt, this.lastError, this.lastPeer});

  /// 上次成功同步时间戳（epoch 毫秒）。
  final int? lastSuccessAt;

  /// 上次失败的错误码字符串。
  final String? lastError;

  /// 上次同步的对端标签。
  final String? lastPeer;
}

/// 从 `settings.raw[lanSyncSettingsKey]` 解析设置。
LanSyncSettings lanSyncSettingsFromRaw(
  Object? value, {
  required String fallbackDeviceName,
}) {
  if (value is! Map) {
    return LanSyncSettings.defaults.copyWith(deviceName: fallbackDeviceName);
  }
  final deviceName = _string(value['deviceName']).trim();
  return LanSyncSettings(
    deviceName: deviceName.isEmpty ? fallbackDeviceName : deviceName,
    port: parseLanSyncPort(value['port']),
    pullMode: LanSyncPullMode.fromWire(_string(value['pullMode'])),
    sharePolicy: LanSyncSharePolicy.fromWire(_string(value['sharePolicy'])),
    identity: LanSyncIdentity(
      deviceId: _string(value['deviceId']).trim(),
      datasetEpoch: _string(value['datasetEpoch']).trim(),
    ),
    status: LanSyncLastStatus(
      lastSuccessAt: _positiveInt(value['lastSuccessAt']),
      lastError: _nonEmptyString(value['lastError']),
      lastPeer: _nonEmptyString(value['lastPeer']),
    ),
    peerWatermarks: _parseWatermarks(value['peerWatermarks']),
  );
}

/// 把端口值夹到可配置区间；非法或缺失时回落到 [lanSyncDefaultPort]。
int parseLanSyncPort(Object? value) {
  if (value is! num) return lanSyncDefaultPort;
  return value.round().clamp(lanSyncMinPort, lanSyncMaxPort);
}

/// 同网段上一台正在共享的设备。
class DiscoveredLanHost {
  /// 以发现字段构造。
  const new({
    required this.instanceId,
    required this.deviceName,
    required this.address,
    required this.port,
    required this.protocolVersion,
    this.deviceKind = '',
    this.allowsBidirectional = true,
  });

  /// 对端这次共享会话的随机标识。
  final String instanceId;

  /// 对端展示的设备名；没有时为空串。
  final String deviceName;

  /// 对端的 IPv4 地址。
  final String address;

  /// 对端共享服务端监听的 TCP 端口。
  final int port;

  /// 对端的协议版本。
  final int protocolVersion;

  /// 对端设备类型（桌面 / 手机）；旧报文缺失时为空串。
  final String deviceKind;

  /// 对端当前是否允许一键双向增量同步。
  final bool allowsBidirectional;

  /// 是否与本机协议版本一致。
  bool get isCompatible => protocolVersion == lanSyncProtocolVersion;

  /// 设备名与地址拼成的展示标签；没有名字时只给地址。
  String get label => deviceName.isEmpty ? address : '$deviceName（$address）';

  /// 对端共享服务端的根地址。
  Uri get baseUri => Uri.parse('http://$address:$port/');

  /// 编码成一条发现应答报文。
  Map<String, Object?> toWire() => <String, Object?>{
    'service': lanSyncServiceName,
    'version': protocolVersion,
    'kind': lanSyncDiscoveryReplyKind,
    'instanceId': instanceId,
    'device': deviceName,
    'port': port,
    if (deviceKind.isNotEmpty) 'deviceKind': deviceKind,
    'allowsBidirectional': allowsBidirectional,
  };
}

/// 一条「有人在吗」的发现查询报文。
Map<String, Object?> lanSyncDiscoveryQueryWire() => <String, Object?>{
  'service': lanSyncServiceName,
  'version': lanSyncProtocolVersion,
  'kind': lanSyncDiscoveryQueryKind,
};

/// 解析一条发现应答报文；无效时返回 `null`。
DiscoveredLanHost? parseDiscoveredLanHost(
  Object? value, {
  required String address,
}) {
  if (value is! Map) return null;
  if (_string(value['service']) != lanSyncServiceName) return null;
  if (_string(value['kind']) != lanSyncDiscoveryReplyKind) return null;

  final version = _positiveInt(value['version']);
  if (version == null || !_isUsableIPv4(address)) return null;

  final port = _positiveInt(value['port']);
  if (port == null || port < lanSyncMinPort || port > lanSyncMaxPort) {
    return null;
  }

  return DiscoveredLanHost(
    instanceId: _string(value['instanceId']),
    deviceName: _string(value['device']).trim(),
    address: address,
    port: port,
    protocolVersion: version,
    deviceKind: _string(value['deviceKind']).trim(),
    allowsBidirectional:
        value['allowsBidirectional'] is! bool ||
        value['allowsBidirectional']! as bool,
  );
}

/// 解析用户手动输入的 `IP` 或 `IP:端口`（供 UDP 广播被拦截时直连）。
///
/// 格式无效或端口越界时返回 `null`。
DiscoveredLanHost? parseManualLanHost(
  String rawInput, {
  int defaultPort = lanSyncDefaultPort,
}) {
  var text = rawInput.trim();
  if (text.startsWith('http://')) text = text.substring('http://'.length);
  if (text.endsWith('/')) text = text.substring(0, text.length - 1);
  if (text.isEmpty) return null;

  final colon = text.indexOf(':');
  final address = colon < 0 ? text : text.substring(0, colon).trim();
  if (!_isUsableIPv4(address)) return null;

  var port = defaultPort;
  if (colon >= 0) {
    final parsed = int.tryParse(text.substring(colon + 1).trim());
    if (parsed == null || parsed < lanSyncMinPort || parsed > lanSyncMaxPort) {
      return null;
    }
    port = parsed;
  }

  return DiscoveredLanHost(
    instanceId: 'manual-$address:$port',
    deviceName: '',
    address: address,
    port: port,
    protocolVersion: lanSyncProtocolVersion,
  );
}

Map<String, LanSyncPeerWatermark> _parseWatermarks(Object? raw) {
  if (raw is! Map) return const <String, LanSyncPeerWatermark>{};
  final result = <String, LanSyncPeerWatermark>{};
  for (final entry in raw.entries) {
    final parsed = LanSyncPeerWatermark.fromRaw(entry.value);
    if (parsed != null) result[parsed.peerDeviceId] = parsed;
  }
  return _cappedWatermarks(result);
}

Map<String, LanSyncPeerWatermark> _cappedWatermarks(
  Map<String, LanSyncPeerWatermark> input,
) {
  if (input.length <= lanSyncMaxTrackedPeers) return input;
  final sorted = input.values.toList()
    ..sort((a, b) => b.lastSyncedAt.compareTo(a.lastSyncedAt));
  return <String, LanSyncPeerWatermark>{
    for (final entry in sorted.take(lanSyncMaxTrackedPeers))
      entry.peerDeviceId: entry,
  };
}

bool _isUsableIPv4(String value) {
  if (value.isEmpty || value == lanSyncUnspecifiedAddress) return false;
  final parts = value.split('.');
  if (parts.length != ipv4PartCount) return false;
  for (final part in parts) {
    if (part.isEmpty || part.length > ipv4PartMaxDigits) return false;
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > ipv4OctetMax) return false;
    if (part.length > 1 && part.startsWith('0')) return false;
  }
  return true;
}

String _string(Object? value) => value is String ? value : '';

String? _nonEmptyString(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

int? _positiveInt(Object? value) {
  if (value is! num) return null;
  final result = value.round();
  return result > 0 ? result : null;
}

int _nonNegativeInt(Object? value) {
  if (value is! num) return 0;
  final result = value.round();
  return result < 0 ? 0 : result;
}
