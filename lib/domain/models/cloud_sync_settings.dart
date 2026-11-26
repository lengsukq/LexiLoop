/// Next.js 云端同步的本机配置、凭据与增量水位线模型（纯 Dart）。
///
/// 与 WebDAV 同理：`password` 只落在本机 `settings` 表中，导出 JSON 备份时由
/// [cloudSyncValueForExport] 自动剥离，且不参与局域网/云端同步合并。
library;

import 'package:lexiloop/core/constants.dart';

/// 云端同步敏感字段名列表（重置地址时一并清理）。
const List<String> cloudSyncCredentialFieldNames = <String>[
  'baseUrl',
  'password',
];

/// 云端同步方式。
enum CloudSyncMode {
  /// 双向增量合并（推荐）：拉取云端变更并推送本机变更，双方一条不删。
  bidirectional('BIDIRECTIONAL'),

  /// 仅拉取合并：把云端变更合入本机，不改动云端数据。
  pullMerge('PULL_MERGE'),

  /// 用云端数据覆盖本机：整体替换本机数据库（需二次确认）。
  pullReplace('PULL_REPLACE');

  new(this.wire);

  /// 持久化与线上传输标识。
  final String wire;

  /// 按标识反查；未知值安全回落到 [bidirectional]。
  static CloudSyncMode fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return CloudSyncMode.bidirectional;
  }
}

/// 连接 Next.js 服务端所需的地址与可选登录密码。
class CloudSyncCredential {
  /// 以服务器根地址与可选密码构造。
  const new({required this.baseUrl, this.password = ''});

  /// 归一化后的 Next.js 根地址（无尾斜杠，如 `https://lexiloop.vercel.app`）。
  final String baseUrl;

  /// 可选的 `LEXILOOP_PASSWORD`；未设密码的实例可为空串。
  final String password;

  /// 根地址是否非空且格式合法。
  bool get isValid => normalizeCloudSyncBaseUrl(baseUrl) != null;

  /// 转为可写入 `settings` 的映射。
  Map<String, Object?> toStorage() => <String, Object?>{
    'baseUrl': baseUrl,
    if (password.isNotEmpty) 'password': password,
  };
}

/// 最近一次云端同步的成败快照。
class CloudSyncLastStatus {
  /// 以时间、错误码、云端词数与摘要构造。
  const new({
    this.lastSuccessAt,
    this.lastError,
    this.lastServerWordCount,
    this.lastSummary,
  });

  /// 最近一次成功同步时间戳（epoch 毫秒）。
  final int? lastSuccessAt;

  /// 最近一次失败错误码。
  final String? lastError;

  /// 最近一次握手/同步观察到的云端词条数。
  final int? lastServerWordCount;

  /// 最近一次同步的简短战果描述。
  final String? lastSummary;
}

/// 与当前 Next.js 云端实例之间的增量同步水位线。
class CloudSyncWatermark {
  /// 以服务端标识、纪元与双侧游标构造。
  const new({
    required this.serverDeviceId,
    required this.serverDatasetEpoch,
    required this.serverCursorMs,
    this.localCursorMs = 0,
  });

  /// 服务端持久化 `deviceId`。
  final String serverDeviceId;

  /// 上次同步时服务端的 `datasetEpoch`；变化时自动回退全量拉取。
  final String serverDatasetEpoch;

  /// 上次拉取时服务端的快照时钟（下次拉取作为 `since`）。
  final int serverCursorMs;

  /// 上次推送时本机的导出时钟。
  final int localCursorMs;

  /// 转为持久化映射。
  Map<String, Object?> toStorage() => <String, Object?>{
    'serverDeviceId': serverDeviceId,
    'serverDatasetEpoch': serverDatasetEpoch,
    'serverCursorMs': serverCursorMs,
    'localCursorMs': localCursorMs,
  };

  /// 从原始对象解析；缺失服务端 ID 时返回 `null`。
  static CloudSyncWatermark? fromRaw(Object? raw) {
    if (raw is! Map) return null;
    final id = _trimmedOrNull(raw['serverDeviceId']);
    if (id == null) return null;
    return CloudSyncWatermark(
      serverDeviceId: id,
      serverDatasetEpoch: _string(raw['serverDatasetEpoch']).trim(),
      serverCursorMs: _nonNegInt(raw['serverCursorMs']),
      localCursorMs: _nonNegInt(raw['localCursorMs']),
    );
  }
}

/// 本机云端同步完整设置。
class CloudSyncSettings {
  /// 以凭据、模式、状态与水位线构造。
  const new({
    this.credential,
    this.mode = CloudSyncMode.bidirectional,
    this.status = const CloudSyncLastStatus(),
    this.watermark,
  });

  /// 未配置时的默认设置。
  static const CloudSyncSettings defaults = CloudSyncSettings();

  /// Next.js 服务器凭据；未填写地址时为 `null`。
  final CloudSyncCredential? credential;

  /// 当前选中的同步模式。
  final CloudSyncMode mode;

  /// 最近一次同步状态。
  final CloudSyncLastStatus status;

  /// 与当前服务器对应的增量同步水位线。
  final CloudSyncWatermark? watermark;

  /// 是否已配置合法服务器地址。
  bool get isConfigured => credential?.isValid ?? false;

  /// 覆盖指定字段，其余保持不变。
  CloudSyncSettings copyWith({
    CloudSyncCredential? credential,
    CloudSyncMode? mode,
    CloudSyncLastStatus? status,
    CloudSyncWatermark? watermark,
    bool clearWatermark = false,
  }) => CloudSyncSettings(
    credential: credential ?? this.credential,
    mode: mode ?? this.mode,
    status: status ?? this.status,
    watermark: clearWatermark ? null : (watermark ?? this.watermark),
  );

  /// 序列化为 `settings.raw[cloudSyncSettingsKey]` 的结构。
  Map<String, Object?> toStorage() => <String, Object?>{
    if (credential != null) ...credential!.toStorage(),
    'mode': mode.wire,
    if (status.lastSuccessAt != null) 'lastSuccessAt': status.lastSuccessAt,
    if (status.lastError != null) 'lastError': status.lastError,
    if (status.lastServerWordCount != null)
      'lastServerWordCount': status.lastServerWordCount,
    if (status.lastSummary != null) 'lastSummary': status.lastSummary,
    if (watermark != null) 'watermark': watermark!.toStorage(),
  };
}

/// 归一化服务器根地址：去掉尾斜杠并校验 `http`/`https` 与 host；非法返回 `null`。
String? normalizeCloudSyncBaseUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final normalizedPath = uri.path.replaceAll(RegExp(r'/+$'), '');
  return Uri(
    scheme: uri.scheme,
    userInfo: uri.userInfo,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: normalizedPath,
  ).toString();
}

/// 从 `settings.raw[cloudSyncSettingsKey]` 解析云端同步设置。
CloudSyncSettings cloudSyncSettingsFromRaw(Object? raw) {
  if (raw is! Map) return CloudSyncSettings.defaults;
  final baseUrl = _string(raw['baseUrl']).trim();
  final password = _string(raw['password']);
  final credential = baseUrl.isEmpty
      ? null
      : CloudSyncCredential(baseUrl: baseUrl, password: password);
  return CloudSyncSettings(
    credential: credential,
    mode: CloudSyncMode.fromWire(_string(raw['mode'])),
    status: CloudSyncLastStatus(
      lastSuccessAt: _positiveInt(raw['lastSuccessAt']),
      lastError: _trimmedOrNull(raw['lastError']),
      lastServerWordCount: _nonNegIntOrNull(raw['lastServerWordCount']),
      lastSummary: _trimmedOrNull(raw['lastSummary']),
    ),
    watermark: CloudSyncWatermark.fromRaw(raw['watermark']),
  );
}

/// 导出备份时剥离密码与运行期易变状态，只保留服务器地址与模式偏好。
Map<String, Object?> cloudSyncValueForExport(Object? raw) {
  if (raw is! Map) return const <String, Object?>{};
  final result = <String, Object?>{};
  final baseUrl = _trimmedOrNull(raw['baseUrl']);
  if (baseUrl != null) result['baseUrl'] = baseUrl;
  final mode = _trimmedOrNull(raw['mode']);
  if (mode != null) result['mode'] = mode;
  return result;
}

/// 用于备份指纹计算的稳定视图：剔除密码与瞬态同步时间/水位线。
Map<String, Object?> cloudSyncValueForFingerprint(Object? raw) =>
    cloudSyncValueForExport(raw);

/// 将常量重新导出便于 domain 消费方统一引用键名。
const String cloudSyncKey = cloudSyncSettingsKey;

String _string(Object? value) => value is String ? value : '';

String? _trimmedOrNull(Object? value) {
  final text = _string(value).trim();
  return text.isEmpty ? null : text;
}

int? _positiveInt(Object? value) {
  if (value is! num) return null;
  final rounded = value.round();
  return rounded > 0 ? rounded : null;
}

int _nonNegInt(Object? value) => _nonNegIntOrNull(value) ?? 0;

int? _nonNegIntOrNull(Object? value) {
  if (value is! num) return null;
  final rounded = value.round();
  return rounded < 0 ? null : rounded;
}
