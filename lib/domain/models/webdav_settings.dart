/// WebDAV 远程备份的设置模型。
///
/// **为什么建模成两个对象**：连接凭据（地址 / 目录 / 账号 / 密码）与运行状态
/// （周期、上次成功、上次失败、数据检查点）的生命周期完全不同——前者只在
/// 用户编辑设置时变，后者每次备份都会变。摊平成一个 8 字段的类会让
/// 「读状态」与「写凭据」两件事共用同一个构造点。
///
/// **为什么存在 `settings.raw` 而不是新建表**：与 `llmConfig`、
/// `merriamWebsterDictionaryKey` 走同一条既有机制——未建模的键由
/// `AppSettings.raw` 原样带出、覆盖写回。这样不必动 schema，也不必写迁移。
///
/// **密码的导出例外**：备份文件会被上传到这台 WebDAV 服务器上，
/// 把该服务器的密码写进这份文件等于把它交给服务器。导出侧因此调用
/// [webdavValueForExport] 剥掉密码（详见该函数的说明）。
///
/// 本文件必须保持纯 Dart（`lib/domain` 的守卫会检查）。
library;

import 'package:lexiloop/core/constants.dart';

/// 远程备份设置在键值表里的键名。
const String webdavSettingsKey = 'webdavBackup';

/// 凭据在存储映射里的四个字段名。
///
/// 导出剥密码与界面「只清凭据、保留状态」都需要按名逐个处理，
/// 集中在这里可以避免三处各抄一份拼错的字符串。
const List<String> webdavCredentialFieldNames = <String>[
  'baseUrl',
  'directory',
  'username',
  'password',
];

/// 允许的 URL 协议：自建 NAS 常用 http（内网），公网服务用 https。
const Set<String> webdavAllowedSchemes = <String>{'http', 'https'};

/// WebDAV 连接凭据。
///
/// 四个字段都非空且地址合法时才算「已配置」（[isConfigured]）；
/// 解析失败一律返回 `null`，由调用方抛「未配置」错误或直接把按钮置灰。
class WebdavCredential {
  /// 以各字段构造（地址与目录应已归一化，见 [parse]）。
  const new({
    required this.baseUrl,
    required this.directory,
    required this.username,
    required this.password,
  });

  /// 服务器根地址，已去尾斜杠，例如 `https://dav.example.com/dav`。
  final String baseUrl;

  /// 相对 [baseUrl] 的备份目录，已补前后斜杠，例如 `/LexiLoop/`。
  final String directory;

  /// 登录用户名。
  final String username;

  /// 登录密码（多数服务要求「应用专用密码」）。
  final String password;

  /// 凭据是否完整可用。
  bool get isConfigured =>
      baseUrl.isNotEmpty && username.isNotEmpty && password.isNotEmpty;

  /// 从存储值解析；缺字段或地址非法时返回 `null`。
  static WebdavCredential? parse(Object? value) {
    if (value is! Map) return null;
    final baseUrl = _normalizeBaseUrl(value['baseUrl']);
    if (baseUrl == null) return null;
    final username = _string(value['username']);
    final password = _string(value['password']);
    if (username.isEmpty || password.isEmpty) return null;
    return WebdavCredential(
      baseUrl: baseUrl,
      directory: normalizeWebdavDirectory(_string(value['directory'])),
      username: username,
      password: password,
    );
  }

  /// 目录链：从最外层到目标目录，供逐级 `MKCOL` 使用。
  ///
  /// 例：`baseUrl=https://h/dav`、`directory=/a/b/` →
  /// `[https://h/dav/a/, https://h/dav/a/b/]`。
  ///
  /// **每一级都以 `/` 结尾**：RFC 4918 里集合 URL 的规范形态带尾斜杠，
  /// 部分服务（如 Apache mod_dav）对不带斜杠的 `PROPFIND` 会按「资源不存在」
  /// 回答，于是「目录已存在」被误判成「需要建目录」。路径段末尾追加一个空段
  /// 正是 `Uri` 表达尾斜杠的方式。
  List<Uri> directoryChain() {
    final base = Uri.parse(baseUrl);
    final baseSegments = _nonEmptySegments(base.path);
    final names = _nonEmptySegments(directory);
    return <Uri>[
      for (var depth = 1; depth <= names.length; depth += 1)
        base.replace(
          pathSegments: <String>[
            ...baseSegments,
            ...names.take(depth),
            _trailingSlashSegment,
          ],
        ),
    ];
  }

  /// 目标目录的 URL（目录名为空时即 [baseUrl]）。
  Uri get directoryUri {
    final chain = directoryChain();
    return chain.isEmpty ? Uri.parse(baseUrl) : chain.last;
  }

  /// 目标目录里某个文件的 URL；文件名按路径段编码。
  Uri fileUri(String fileName) {
    final directory = directoryUri;
    return directory.replace(
      pathSegments: <String>[..._nonEmptySegments(directory.path), fileName],
    );
  }

  /// 写回存储的形态。
  Map<String, Object?> toStorage() => <String, Object?>{
    'baseUrl': baseUrl,
    'directory': directory,
    'username': username,
    'password': password,
  };
}

/// WebDAV 远程备份的运行状态。
class WebdavBackupState {
  /// 以各字段构造。
  const new({
    required this.autoIntervalMinutes,
    this.lastSuccessAt,
    this.lastError,
    this.lastCheckpoint,
  });

  /// 从存储值解析；非法项各自兜底。
  ///
  /// 写成工厂构造：它就是这个类唯一的「从裸值创建」入口，
  /// 与生成式构造函数并列，调用方读起来是同一件事。
  /// 从存储值解析；非法项各自兜底。
  ///
  /// **豁免 `prefer_constructors_over_static_methods`**：仓库统一的解析入口
  /// 就叫 `parse` / `fromWire` / `fromCode`（见 `AppErrorCode.fromCode`），
  /// 保持一致比满足这条建议更重要；工厂构造在同名约束下写不出这个名字。
  // ignore: prefer_constructors_over_static_methods
  static WebdavBackupState parse(Object? value) {
    if (value is! Map) {
      return const WebdavBackupState(
        autoIntervalMinutes: defaultWebdavAutoIntervalMinutes,
      );
    }
    return WebdavBackupState(
      autoIntervalMinutes: _interval(value['autoIntervalMinutes']),
      lastSuccessAt: _timestamp(value['lastSuccessAt']),
      lastError: _string(value['lastError']).isEmpty
          ? null
          : _string(value['lastError']),
      lastCheckpoint: _string(value['lastCheckpoint']).isEmpty
          ? null
          : _string(value['lastCheckpoint']),
    );
  }

  /// 自动备份周期（分钟）；`0` 表示关闭自动备份。
  final int autoIntervalMinutes;

  /// 上次成功上传的时间戳（epoch 毫秒）；从未成功时为 `null`。
  final int? lastSuccessAt;

  /// 上次失败的错误码字符串（`AppErrorCode.code`）；上次成功之后没有失败时为 `null`。
  final String? lastError;

  /// 上次成功上传时的数据检查点（`"<最近作答时间>:<词条数>"`）。
  ///
  /// 自动备份靠它判断「数据变了没有」：与当前检查点相同就跳过，
  /// 避免每天定时上传一份内容完全一样的备份。
  final String? lastCheckpoint;

  /// 自动备份是否启用。
  bool get autoEnabled => autoIntervalMinutes > 0;

  /// 周期对应的时间跨度。
  Duration get autoInterval => Duration(minutes: autoIntervalMinutes);

  /// 覆盖若干个状态字段，其余原样保留。
  WebdavBackupState copyWith({
    int? autoIntervalMinutes,
    int? lastSuccessAt,
    String? lastError,
    String? lastCheckpoint,
    bool clearError = false,
  }) => WebdavBackupState(
    autoIntervalMinutes: autoIntervalMinutes ?? this.autoIntervalMinutes,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
    lastCheckpoint: lastCheckpoint ?? this.lastCheckpoint,
  );

  /// 写回存储的形态。
  Map<String, Object?> toStorage() => <String, Object?>{
    'autoIntervalMinutes': autoIntervalMinutes,
    if (lastSuccessAt != null) 'lastSuccessAt': lastSuccessAt,
    if (lastError != null) 'lastError': lastError,
    if (lastCheckpoint != null) 'lastCheckpoint': lastCheckpoint,
  };
}

/// 远程备份设置：连接凭据（可缺）+ 运行状态。
class WebdavSettings {
  /// 以凭据与状态构造。
  const new({required this.credential, required this.state});

  /// 连接凭据；未配置或配置不完整时为 `null`。
  final WebdavCredential? credential;

  /// 运行状态（始终存在，未配置时取默认周期）。
  final WebdavBackupState state;

  /// 是否可以直接发起远程操作。
  bool get isConfigured => credential != null;

  /// 未配置时的默认设置。
  static const WebdavSettings defaults = WebdavSettings(
    credential: null,
    state: WebdavBackupState(
      autoIntervalMinutes: defaultWebdavAutoIntervalMinutes,
    ),
  );
}

/// 从 `settings.raw[webdavSettingsKey]` 解析设置。
WebdavSettings webdavSettingsFromRaw(Object? value) => WebdavSettings(
  credential: WebdavCredential.parse(value),
  state: WebdavBackupState.parse(value),
);

/// 序列化为可写回 `settings.raw` 的映射。
///
/// **为什么把凭据与状态合到一个映射里**：它们同属一个存储键。分两个键会让
/// 「保存密码」与「记录上次成功」各写半行，任何一次读-改-写竞争都可能
/// 让其中一半丢失。
Map<String, Object?> webdavSettingsToStorage(WebdavSettings settings) =>
    webdavStorageFromFields(
      credential: settings.credential?.toStorage() ?? const <String, Object?>{},
      state: settings.state,
    );

/// 用**原始凭据字段**与状态拼出存储映射。
///
/// **为什么要有「原始字段」这个入口**：凭据可以处于「地址与账号已填、
/// 密码还没填」的半成品状态，此时 [WebdavCredential.parse] 返回 `null`。
/// 界面与状态存储都必须以原始字段为合并基准，否则一次状态更新
/// （例如改自动备份周期）就会把用户刚填的两栏抹掉。
///
/// 只有 [webdavCredentialFieldNames] 里的四个键会被带出：状态键与凭据键
/// 同处一个映射，不设边界的话 `toStorage` 与原始字段会互相覆盖。
Map<String, Object?> webdavStorageFromFields({
  required Map<String, Object?> credential,
  required WebdavBackupState state,
}) => <String, Object?>{
  for (final field in webdavCredentialFieldNames)
    if (credential.containsKey(field)) field: credential[field],
  ...state.toStorage(),
};

/// 导出备份时使用的 `webdavBackup` 值：**剥掉密码**，其余字段保留。
///
/// **为什么必须剥**：这份 JSON 会被上传到该 WebDAV 服务器（以及可能被分享给
/// 别人）。把服务器自己的密码写进上传到该服务器的文件里，等于把凭据交给了
/// 服务器与任何拿到备份的人。剥掉之后，远端恢复会带回地址与账号，
/// 只需重新填密码——界面上有对应提示。
///
/// 非映射（或未配置）时原样返回，调用方不必先做类型判断。
Object? webdavValueForExport(Object? value) {
  if (value is! Map) return value;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is String && key != 'password') result[key] = entry.value;
  }
  return result;
}

/// 归一化目录：补前后斜杠，把多个斜杠压成一个。
///
/// 空串归一为 `/`（放在服务器根目录），因为绝大多数 WebDAV 服务
/// 对「根目录」的 `PROPFIND` 只接受带尾斜杠的路径。
String normalizeWebdavDirectory(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '/';
  final collapsed = trimmed.replaceAll(RegExp('/+'), '/');
  final withLeading = collapsed.startsWith('/') ? collapsed : '/$collapsed';
  return withLeading.endsWith('/') ? withLeading : '$withLeading/';
}

/// 归一化服务器地址：去尾斜杠、校验协议与主机。
///
/// 返回 `null` 表示不是可用的地址（缺少协议、协议不是 http(s)、没有主机）。
String? _normalizeBaseUrl(Object? value) {
  final raw = _string(value).trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (!webdavAllowedSchemes.contains(uri.scheme.toLowerCase())) return null;
  if (uri.host.isEmpty) return null;
  var text = uri.toString();
  while (text.endsWith('/') && text.length > webdavAllowedSchemes.length) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// 用来在路径段末尾表达尾斜杠的空段。
const String _trailingSlashSegment = '';

/// 取一个非空字符串值。
String _string(Object? value) => value is String ? value : '';

/// 路径里非空的段。
List<String> _nonEmptySegments(String path) =>
    path.split('/').where((segment) => segment.isNotEmpty).toList();

/// 自动备份周期：夹到「关闭 … 最长可选项」之间。
int _interval(Object? value) {
  if (value is! num) return defaultWebdavAutoIntervalMinutes;
  return value.round().clamp(0, webdavAutoIntervalOptions.last);
}

/// 时间戳：只接受正数。
int? _timestamp(Object? value) {
  if (value is! num) return null;
  final result = value.round();
  return result > 0 ? result : null;
}
