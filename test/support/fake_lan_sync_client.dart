/// 局域网同步的替身。
///
/// 服务层只依赖三个端口（客户端 / 发现器 / 服务端启动器），
/// 因此这里三个 `Map` 与几个计数器就能覆盖全部分支——协议细节由
/// `test/data/lan_sync/` 下的用例单独钉住。
library;

import 'dart:typed_data';

import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_discovery_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

/// 一台内存里的对端设备。
final class FakeLanSyncClient implements LanSyncClient {
  /// 以握手结果与备份构造。
  new({
    LanSyncHandshake? handshake,
    LanSyncBackup? backup,
    this.handshakeFailure,
    this.downloadFailure,
    this.downloadDelay,
  }) : handshakeResult =
           handshake ??
           const LanSyncHandshake(
             deviceName: 'LexiLoop 手机',
             protocolVersion: lanSyncProtocolVersion,
           ),
       backupResult =
           backup ??
           LanSyncBackup(
             bytes: Uint8List(0),
             fileName: 'lexiloop-backup-2026-10-16-101500.json',
             totalRows: 0,
           );

  /// [handshake] 返回的结果。
  LanSyncHandshake handshakeResult;

  /// [downloadBackup] 返回的结果。
  LanSyncBackup backupResult;

  /// 非空时 [handshake] 抛出它。
  AppError? handshakeFailure;

  /// 非空时 [downloadBackup] 抛出它。
  AppError? downloadFailure;

  /// 非空时 [downloadBackup] 先等待这么久（用来构造「先握手后下载」的时序）。
  Duration? downloadDelay;

  /// 调用顺序（`handshake` / `download`），供断言「先验码再传字节」。
  final List<String> calls = <String>[];

  @override
  Future<LanSyncHandshake> handshake() async {
    calls.add('handshake');
    final failure = handshakeFailure;
    if (failure != null) throw failure;
    return handshakeResult;
  }

  @override
  Future<LanSyncBackup> downloadBackup() async {
    calls.add('download');
    final delay = downloadDelay;
    if (delay != null) await Future<void>.delayed(delay);
    final failure = downloadFailure;
    if (failure != null) throw failure;
    return backupResult;
  }
}

/// 记录每次构造参数的客户端工厂。
final class FakeLanSyncClientFactory {
  /// 以要发给每个客户端的实例构造。
  new(this.client);

  /// 每次 [call] 都返回它。
  final FakeLanSyncClient client;

  /// 每次调用时的（目标设备，配对码）。
  final List<({DiscoveredLanHost host, String code})> calls =
      <({DiscoveredLanHost host, String code})>[];

  /// 工厂函数本体。
  LanSyncClient call(DiscoveredLanHost host, String pairingCode) {
    calls.add((host: host, code: pairingCode));
    return client;
  }
}

/// 一台内存里的对端设备。
final class FakeLanSyncHost implements LanSyncHost {
  /// 以根地址与初始服务次数构造。
  new({Uri? baseUri, this.servedCount = 0, this.stopFailure, this.options})
    : baseUri = baseUri ?? Uri.parse('http://192.168.1.7:8765/');

  @override
  Uri baseUri;

  @override
  int servedCount;

  /// 非空时 [stop] 抛出它。
  Exception? stopFailure;

  /// 启动时收到的选项（用于断言配对码、设备名、端口）。
  LanSyncHostOptions? options;

  /// [stop] 被调用的次数。
  int stopCalls = 0;

  @override
  Future<void> stop() async {
    stopCalls += 1;
    final failure = stopFailure;
    if (failure != null) throw failure;
  }

  /// 模拟服务端成功服务一次拉取。
  void serveOnce() {
    servedCount += 1;
    options?.onServed(servedCount);
  }

  /// 模拟配对码连续错误触顶。
  void lockOut() => options?.onCodeLockout();
}

/// 记录启动参数的共享服务端启动器。
final class FakeLanSyncHostStarter {
  /// 以要返回的服务端构造。
  new({FakeLanSyncHost? host, this.failure}) : host = host ?? FakeLanSyncHost();

  /// 每次调用都返回它。
  final FakeLanSyncHost host;

  /// 非空时抛出它。
  Exception? failure;

  /// 每次启动时的选项。
  final List<LanSyncHostOptions> calls = <LanSyncHostOptions>[];

  /// 启动器本体。
  Future<LanSyncHost> call(LanSyncHostOptions options) async {
    calls.add(options);
    host.options = options;
    final failure = this.failure;
    if (failure != null) throw failure;
    return host;
  }
}

/// 内存里的设备发现器。
final class FakeLanSyncDiscovery implements LanSyncDiscovery {
  /// 以要返回的结果构造。
  new({LanSyncDiscoveryResult? result, this.failure})
    : result = result ?? LanSyncDiscoveryResult.empty;

  /// [discover] 返回的结果。
  LanSyncDiscoveryResult result;

  /// 非空时抛出它。
  Exception? failure;

  /// [discover] 被调用的次数。
  int calls = 0;

  /// 上次调用传入的超时。
  Duration? lastTimeout;

  @override
  Future<LanSyncDiscoveryResult> discover({required Duration timeout}) async {
    calls += 1;
    lastTimeout = timeout;
    final failure = this.failure;
    if (failure != null) throw failure;
    return result;
  }
}

/// 造一台发现结果里的设备。
DiscoveredLanHost fakeDiscoveredHost({
  String instanceId = 'peer-1',
  String deviceName = 'LexiLoop 手机',
  String address = '192.168.1.7',
  int port = 8765,
  int protocolVersion = lanSyncProtocolVersion,
}) => DiscoveredLanHost(
  instanceId: instanceId,
  deviceName: deviceName,
  address: address,
  port: port,
  protocolVersion: protocolVersion,
);
