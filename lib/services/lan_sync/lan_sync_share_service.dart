/// 共享会话的编排：配对码、服务端生命周期、错码踢下线。
///
/// **为什么与会话状态分开**：本类不认识 Riverpod，只回答「现在在不在共享、
/// 配对码是什么、服务了多少次」。界面状态由
/// `lan_sync_providers.dart` 的 `LanSyncShareController` 持有，
/// 于是本类可以脱离 `ProviderScope` 单测。
///
/// **配对码每次开启共享重新生成、只存在内存里**：不落盘意味着它不会进备份、
/// 不会被导出的 JSON 带走（WebDAV 密码需要专门的导出剥离，这里根本不需要）。
library;

import 'dart:math';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/data/backup/backup_export.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/services/backup/backup_naming.dart';
import 'package:lexiloop/services/lan_sync/lan_sync_state_store.dart';

/// 一次共享会话的对外快照。
class LanSyncShareSession {
  /// 以各字段构造。
  const new({
    required this.pairingCode,
    required this.instanceId,
    required this.deviceName,
    required this.baseUri,
    required this.servedCount,
    required this.lockedOut,
  });

  /// 本次会话的配对码（对端要输入的 6 位数字）。
  final String pairingCode;

  /// 本次会话的随机标识。
  final String instanceId;

  /// 本机展示名。
  final String deviceName;

  /// 对端该连的根地址（仅用于界面展示）。
  final Uri baseUri;

  /// 已经成功服务过多少次拉取。
  final int servedCount;

  /// 是否因配对码连续错误而被自动停止。
  ///
  /// `true` 时服务端已经被停掉，界面要显示「共享已自动停止」而不是继续
  /// 展示一个已经无效的配对码。
  final bool lockedOut;

  /// 是否仍在正常共享。
  bool get isSharing => !lockedOut;

  /// 覆盖若干字段，其余原样保留。
  LanSyncShareSession copyWith({int? servedCount, bool? lockedOut}) =>
      LanSyncShareSession(
        pairingCode: pairingCode,
        instanceId: instanceId,
        deviceName: deviceName,
        baseUri: baseUri,
        servedCount: servedCount ?? this.servedCount,
        lockedOut: lockedOut ?? this.lockedOut,
      );
}

/// 共享服务端会话的编排。
class LanSyncShareService {
  /// 以导出器、服务端启动器与状态存储构造。
  ///
  /// [codeGenerator] 与 [instanceIdGenerator] 是可测性接缝：默认用
  /// `Random.secure()`，测试里换成固定值即可断言界面上的那串数字。
  new(
    this._exporter,
    this._starter,
    this._states, {
    String Function()? codeGenerator,
    String Function()? instanceIdGenerator,
  }) : _generateCode = codeGenerator ?? _randomPairingCode,
       _generateInstanceId = instanceIdGenerator ?? _randomInstanceId;

  final BackupExporter _exporter;
  final LanSyncHostStarter _starter;
  final LanSyncStateStore _states;
  final String Function() _generateCode;
  final String Function() _generateInstanceId;

  LanSyncHost? _host;
  LanSyncShareSession? _session;
  void Function()? _notifyServed;
  void Function()? _notifyLockedOut;

  /// 当前共享会话；未共享时为 `null`。
  LanSyncShareSession? get session => _session;

  /// 是否已经开启共享。
  bool get isSharing => _session?.isSharing ?? false;

  /// 开启共享；已经开着时原样返回同一会话，不会起第二个服务端。
  ///
  /// [onServed] 与 [onLockedOut] 是给界面层的通知钩子：服务次数变了、
  /// 或者被错码踢下线了，界面需要重建。
  Future<LanSyncShareSession> start({
    required void Function() onServed,
    required void Function() onLockedOut,
  }) async {
    final existing = _session;
    if (existing != null && existing.isSharing) return existing;

    _notifyServed = onServed;
    _notifyLockedOut = onLockedOut;
    // 上一次会话（例如刚被错码踢下线）可能还在收尾，端口还没释放。
    // `stop()` 是幂等的，这里先等它，避免新会话撞上「端口已被占用」。
    await _host?.stop();
    _host = null;

    final settings = await _states.load();
    final code = _generateCode();
    final instanceId = _generateInstanceId();
    final host = await _starter(
      LanSyncHostOptions(
        deviceName: settings.deviceName,
        port: settings.port,
        pairingCode: code,
        instanceId: instanceId,
        backupSource: _exportBackup,
        onServed: _handleServed,
        onCodeLockout: _handleCodeLockout,
      ),
    );
    _host = host;
    _session = LanSyncShareSession(
      pairingCode: code,
      instanceId: instanceId,
      deviceName: settings.deviceName,
      baseUri: host.baseUri,
      servedCount: host.servedCount,
      lockedOut: false,
    );
    return _session!;
  }

  /// 停止共享；可重复调用。
  Future<void> stop() async {
    final host = _host;
    _host = null;
    _session = null;
    await host?.stop();
  }

  /// 按需导出一份备份。
  ///
  /// **每次请求现导出**：预先缓存会让「开了共享但没人来拉」也占着 27MB 内存，
  /// 而且缓存的那份可能已经落后于最新数据。
  Future<LanSyncBackup> _exportBackup() async {
    final exported = await _exporter.exportToJson();
    return LanSyncBackup(
      bytes: exported.bytes,
      fileName: backupFileName(DateTime.now()),
      totalRows: exported.totalRows,
    );
  }

  /// 服务次数变化：更新快照并通知界面。
  void _handleServed(int servedCount) {
    _session = _session?.copyWith(servedCount: servedCount);
    _notifyServed?.call();
  }

  /// 配对码连续错误到达上限。
  ///
  /// **保留 `_session`、只标记 `lockedOut`**：界面要能说明「为什么突然停了」。
  /// 服务端此时正在自行停止（回调之后主机就会 `stop()`），因此这里不动 `_host`
  /// ——下一次 [start] 会先把它收干净。
  void _handleCodeLockout() {
    _session = _session?.copyWith(lockedOut: true);
    _notifyLockedOut?.call();
  }
}

/// 生成一个 6 位数字配对码。
String _randomPairingCode() =>
    _randomToken(lanSyncPairingCodeAlphabet, lanSyncPairingCodeLength);

/// 生成一个随机会话标识。
String _randomInstanceId() =>
    _randomToken(lanSyncInstanceIdAlphabet, lanSyncInstanceIdLength);

/// 从 [alphabet] 里均匀取 [length] 个字符。
///
/// 用 `Random.secure()` 而不是 `Random()`：配对码是一道门禁，
/// 可预测的伪随机序列等于没有门禁。
String _randomToken(String alphabet, int length) {
  final random = Random.secure();
  final buffer = StringBuffer();
  for (var index = 0; index < length; index += 1) {
    buffer.write(alphabet[random.nextInt(alphabet.length)]);
  }
  return buffer.toString();
}
