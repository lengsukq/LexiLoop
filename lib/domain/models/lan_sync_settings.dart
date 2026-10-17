/// 局域网同步的设置模型与发现报文模型。
///
/// **为什么与 WebDAV 的设置模型不同构**：那边刻意把「连接凭据」与「运行状态」
/// 拆成两个对象，因为凭据只在用户编辑时变、状态每次备份都变。这里的
/// `deviceName` / `port` 与状态一样都只是本机配置，没有「半填的凭据」这种
/// 中间态，所以摊平成一个类反而更好读。
///
/// **配对码刻意不在这个模型里**：它只活在主机的**一次共享会话**中
/// （每次开启共享重新生成、只存在内存里）。不落盘有两个直接好处——
/// 不必像 WebDAV 密码那样在导出时做剥离，也不必担心备份文件泄漏配对码。
///
/// **为什么有 `settings.raw` 而不是新建表**：与 `webdavBackup`、`llmConfig`
/// 走同一条既有机制——未建模的键由 `AppSettings.raw` 原样带出、覆盖写回，
/// 因此不必动 schema，也不必写迁移。
///
/// 本文件必须保持纯 Dart（`lib/domain` 的守卫会检查）。
library;

import 'package:lexiloop/core/constants.dart';

/// 局域网同步设置在键值表里的键名。
const String lanSyncSettingsKey = 'lanSync';

/// 设备名的兜底值。
const String lexiloopDeviceNameDefault = 'LexiLoop';

/// 按平台推导默认设备名。
///
/// **为什么带平台后缀**：本特性的设备列表按设备名展示，两台设备都叫
/// `LexiLoop` 时用户根本分不清该选哪个——而这恰恰是最常见的情况
/// （macOS 与 Android 各一台）。带后缀之后「LexiLoop 桌面 / LexiLoop 手机」
/// 一眼可辨，且不需要读 `Platform.localHostname`（那要 `dart:io`，
/// 而本文件必须是纯 Dart）。
String defaultLanSyncDeviceName({required bool isDesktop}) => isDesktop
    ? '$lexiloopDeviceNameDefault 桌面'
    : '$lexiloopDeviceNameDefault 手机';

/// 从对端拉取数据时的合并方式。
///
/// **为什么是一个持久化的选择而不是每次弹窗**：用户的意图通常在几次同步里
/// 保持不变（"我就是要合并"或"我就是要覆盖"）。记住它，减少一次误选；
/// 两种模式各自的确认门仍然保留，误选的代价不会跨过那一道门。
enum LanSyncPullMode {
  /// 把对端的数据并进本机，本机现有数据一条不删。
  merge('MERGE'),

  /// 用对端的数据整体替换本机。
  replace('REPLACE');

  new(this.wire);

  /// 存储标识。
  final String wire;

  /// 按存储标识反查；未知值回落到 [merge]。
  ///
  /// **回落方向不能反**：一个版本不认识的值意味着它来自更新版本，
  /// 此时按「合并」处理最安全——合并不会删数据，覆盖会。
  static LanSyncPullMode fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return LanSyncPullMode.merge;
  }
}

/// 局域网同步的本机配置与上次同步状态。
class LanSyncSettings {
  /// 以各字段构造。
  ///
  /// [port] 应当已经过 [parseLanSyncPort] 归一；构造器不重复夹取，
  /// 是为了让「非法端口」只有一个入口能被修好。
  const new({
    required this.deviceName,
    required this.port,
    this.pullMode = LanSyncPullMode.merge,
    this.lastSuccessAt,
    this.lastError,
    this.lastPeer,
  });

  /// 未配置任何内容时的默认值。
  ///
  /// [deviceName] 为空表示「用平台推导的兜底名」：默认名依赖平台，
  /// 而本文件是纯 Dart，因此把兜底交给调用方在解析时传入
  /// （见 [lanSyncSettingsFromRaw] 的 `fallbackDeviceName`）。
  static const LanSyncSettings defaults = LanSyncSettings(
    deviceName: '',
    port: lanSyncDefaultPort,
  );

  /// 本机在发现列表里的展示名；空串表示使用平台推导的兜底名。
  final String deviceName;

  /// 共享服务端监听的 TCP 端口。
  final int port;

  /// 拉取时的合并方式（默认合并）。
  final LanSyncPullMode pullMode;

  /// 上次成功拉取的时间戳（epoch 毫秒）；从未成功时为 `null`。
  final int? lastSuccessAt;

  /// 上次失败的错误码字符串（`AppErrorCode.code` 的取值）。
  ///
  /// **只存错误码、不存文案**：文案由错误码的 `defaultMessage` 唯一决定，
  /// 存进设置表会让改了文案的版本读回旧句子。
  final String? lastError;

  /// 上次同步的对端标签（`设备名（地址）`），只用于状态行。
  final String? lastPeer;

  /// 展示名：用户填了就用它，否则用平台兜底名。
  String effectiveDeviceName({required String fallback}) =>
      deviceName.isEmpty ? fallback : deviceName;

  /// 覆盖若干字段，其余原样保留。
  ///
  /// [clearError] / [clearPeer] 是 `copyWith` 传 `null` 无法表达的「清空」：
  /// 一次成功同步必须能把上次的失败原因抹掉，否则状态行会一直挂着旧错误。
  LanSyncSettings copyWith({
    String? deviceName,
    int? port,
    LanSyncPullMode? pullMode,
    int? lastSuccessAt,
    String? lastError,
    String? lastPeer,
    bool clearError = false,
    bool clearPeer = false,
  }) => LanSyncSettings(
    deviceName: deviceName ?? this.deviceName,
    port: port ?? this.port,
    pullMode: pullMode ?? this.pullMode,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
    lastPeer: clearPeer ? null : (lastPeer ?? this.lastPeer),
  );

  /// 写回 `settings.raw[lanSyncSettingsKey]` 的形态。
  ///
  /// 空字段不写：`deviceName` 为空时落盘一个 `""` 会让「用户还没命名」
  /// 与「用户把名字清空了」变得无法区分，而两者的行为应当一样（都用兜底名）。
  Map<String, Object?> toStorage() => <String, Object?>{
    if (deviceName.isNotEmpty) 'deviceName': deviceName,
    'port': port,
    'pullMode': pullMode.wire,
    if (lastSuccessAt != null) 'lastSuccessAt': lastSuccessAt,
    if (lastError != null) 'lastError': lastError,
    if (lastPeer != null) 'lastPeer': lastPeer,
  };
}

/// 从 `settings.raw[lanSyncSettingsKey]` 解析设置。
///
/// [fallbackDeviceName] 是平台推导的兜底名（见 [defaultLanSyncDeviceName]）：
/// 纯 Dart 层取不到平台，因此必须由调用方注入。
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
    lastSuccessAt: _positiveInt(value['lastSuccessAt']),
    lastError: _nonEmptyString(value['lastError']),
    lastPeer: _nonEmptyString(value['lastPeer']),
  );
}

/// 把端口值夹到可配置区间；非法或缺失时回落到 [lanSyncDefaultPort]。
///
/// 返回 `int` 而不是 `int?`：端口总是有一个可用值，让调用方去处理 `null`
/// 只会把同一个兜底写很多遍。
int parseLanSyncPort(Object? value) {
  if (value is! num) return lanSyncDefaultPort;
  return value.round().clamp(lanSyncMinPort, lanSyncMaxPort);
}

/// 同网段上一台正在共享的设备。
///
/// 只建模「选一台来同步」需要的字段：一句展示用的设备名、一个可连的地址、
/// 一个端口、一个协议版本。**不建模配对码**——它是发现之后才由用户输入的，
/// 而发现报文里本来就没有它（有的话等于把门禁贴在门上）。
class DiscoveredLanHost {
  /// 以各字段构造。
  const new({
    required this.instanceId,
    required this.deviceName,
    required this.address,
    required this.port,
    required this.protocolVersion,
  });

  /// 对端这次共享会话的随机标识。
  ///
  /// **为什么需要它**：同一个应用既开着共享、又点了「搜索设备」时，
  /// 会收到自己的应答。按「地址 + 端口」比对会漏掉多网卡与多网段的情况，
  /// 而按会话标识比对是精确的：自己当前会话的标识自己知道。
  final String instanceId;

  /// 对端展示的设备名；没有时为空串。
  final String deviceName;

  /// 对端的 IPv4 地址（发现回复的来源地址）。
  final String address;

  /// 对端共享服务端监听的 TCP 端口。
  final int port;

  /// 对端的协议版本。
  final int protocolVersion;

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
  };
}

/// 一条「有人在吗」的发现查询报文。
///
/// 写成函数而不是常量：它是一个会被 `jsonEncode` 消费的可变映射，
/// 共享同一个常量实例会让任何一处误改污染后续所有请求。
Map<String, Object?> lanSyncDiscoveryQueryWire() => <String, Object?>{
  'service': lanSyncServiceName,
  'version': lanSyncProtocolVersion,
  'kind': lanSyncDiscoveryQueryKind,
};

/// 解析一条发现应答报文。
///
/// **地址为什么是参数而不是报文字段**：对端的地址由接收方从数据报的来源
/// 地址读到，是**观测事实**；写进报文里等于让对方自报家门，既可能撒谎，
/// 也会在 NAT / 多网卡场景下给出一个连不通的地址。
///
/// 返回 `null` 表示**不是本协议的有效应答**：不是映射、服务标识不符、
/// 报文的 `kind` 不是应答、协议版本缺失、地址或端口不可用。发现是收到
/// 谁算谁的场景，任何不合规的报文都只能被忽略——抛异常会让一个畸形的
/// 邻居把整次搜索打断。
///
/// **版本不在这里过滤**：调用方需要区分「没有设备」与「只有版本不兼容的
/// 设备」，后者要报的是「版本不兼容」而不是「没搜到」。
DiscoveredLanHost? parseDiscoveredLanHost(
  Object? value, {
  required String address,
}) {
  if (value is! Map) return null;
  if (_string(value['service']) != lanSyncServiceName) return null;
  if (_string(value['kind']) != lanSyncDiscoveryReplyKind) return null;

  final version = _positiveInt(value['version']);
  if (version == null) return null;
  if (!_isUsableIPv4(address)) return null;

  final port = _positiveInt(value['port']);
  if (port == null) return null;
  if (port < lanSyncMinPort || port > lanSyncMaxPort) return null;

  return DiscoveredLanHost(
    instanceId: _string(value['instanceId']),
    deviceName: _string(value['device']).trim(),
    address: address,
    port: port,
    protocolVersion: version,
  );
}

/// 地址是否是可直接拼进 `http://` 的 IPv4 字面量。
///
/// 只收 IPv4：本版的发现走 IPv4 广播（`InternetAddress.anyIPv4`），
/// 而 IPv6 的地址在 URL 里必须加方括号，放行一个拼不出合法 URL 的字符串
/// 只会在更远的地方炸。
bool _isUsableIPv4(String value) {
  if (value.isEmpty) return false;
  // `0.0.0.0` 是「未指定地址」，永远连不上。同一台机器上向广播地址发包时，
  // 内核有时会把来源地址留成它；把它当成一台设备只会让列表里多一条死条目。
  if (value == lanSyncUnspecifiedAddress) return false;
  final parts = value.split('.');
  if (parts.length != ipv4PartCount) return false;
  for (final part in parts) {
    if (part.isEmpty || part.length > ipv4PartMaxDigits) return false;
    final octet = int.tryParse(part);
    if (octet == null) return false;
    if (octet < 0 || octet > ipv4OctetMax) return false;
    // 前导零在部分解析器里被当成八进制（`010` = 8），直接拒绝。
    if (part.length > 1 && part.startsWith('0')) return false;
  }
  return true;
}

/// 取一个非空字符串值。
String _string(Object? value) => value is String ? value : '';

/// 取一个非空字符串；空串按缺失处理。
String? _nonEmptyString(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

/// 取一个正整数；非正数或非数字按缺失处理。
int? _positiveInt(Object? value) {
  if (value is! num) return null;
  final result = value.round();
  return result > 0 ? result : null;
}
