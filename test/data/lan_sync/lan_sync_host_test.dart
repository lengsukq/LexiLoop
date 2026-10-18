/// 局域网共享服务端的测试。
///
/// **真起一个 `HttpServer` 与一个 UDP 套接字**，只是都绑在回环上、端口由系统
/// 分配：这一层要钉住的正是「我们真的按这套协议说话」——请求方法、路径、
/// 配对码请求头、响应头、状态码映射。替换成假的网络层就什么都测不到了。
///
/// 每个用例用一条独立的发现端口，避免同进程内多个套接字抢同一个 UDP 端口。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_backup.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_host_port.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

import '../../support/free_udp_port.dart';

/// 测试用配对码。
const String testCode = '123456';

/// 一份可辨认的「备份」载荷。
final Uint8List testBackupBytes = Uint8List.fromList(
  utf8.encode('{"format":"lexiloop-json-backup","version":3}'),
);

void main() {
  late _HostFixture fixture;

  setUp(() async {
    fixture = _HostFixture();
    await fixture.start();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  group('配对码', () {
    test('没有配对码头时返回 401', () async {
      final response = await fixture.get(lanSyncHandshakePath);
      expect(response.statusCode, lanSyncStatusUnauthorized);
    });

    test('配对码错误时返回 401，且响应体带错误码', () async {
      final response = await fixture.get(lanSyncHandshakePath, code: '000000');
      expect(response.statusCode, lanSyncStatusUnauthorized);
      final body = jsonDecode(response.body) as Map<String, Object?>;
      expect(body[lanSyncErrorCodeField], AppErrorCode.lanSyncCodeInvalid.code);
    });

    test('拉取路径在配对码错误时同样返回 401，且不导出任何数据', () async {
      final response = await fixture.get(lanSyncBackupPath, code: '000000');
      expect(response.statusCode, lanSyncStatusUnauthorized);
      expect(fixture.exportCalls, isZero);
    });

    test('连续错码到达上限时回调一次并停掉服务', () async {
      for (
        var attempt = 0;
        attempt < lanSyncPairingCodeMaxAttempts;
        attempt++
      ) {
        await fixture.get(lanSyncHandshakePath, code: '000000');
      }
      expect(fixture.lockouts, 1);
      // 服务端已经关了：再连一次应当被拒。
      await expectLater(
        fixture.get(lanSyncHandshakePath),
        throwsA(isA<SocketException>()),
      );
    });

    test('中途成功一次会把错码计数清零', () async {
      for (
        var attempt = 0;
        attempt < lanSyncPairingCodeMaxAttempts - 1;
        attempt++
      ) {
        await fixture.get(lanSyncHandshakePath, code: '000000');
      }
      final ok = await fixture.get(lanSyncHandshakePath, code: testCode);
      expect(ok.statusCode, HttpStatus.ok);
      // 计数已清零，再来满一轮才该被踢下线。
      for (
        var attempt = 0;
        attempt < lanSyncPairingCodeMaxAttempts - 1;
        attempt++
      ) {
        await fixture.get(lanSyncHandshakePath, code: '000000');
      }
      expect(fixture.lockouts, isZero);
    });
  });

  group('握手', () {
    test('配对码正确时返回服务标识、版本与设备名', () async {
      final response = await fixture.get(lanSyncHandshakePath, code: testCode);
      expect(response.statusCode, HttpStatus.ok);

      final handshake = parseLanSyncHandshake(response.body);
      expect(handshake, isNotNull);
      expect(handshake!.deviceName, '测试主机');
      expect(handshake.protocolVersion, lanSyncProtocolVersion);
    });

    test('握手不导出任何数据', () async {
      await fixture.get(lanSyncHandshakePath, code: testCode);
      expect(fixture.exportCalls, isZero);
    });

    test('握手不计入已服务次数', () async {
      await fixture.get(lanSyncHandshakePath, code: testCode);
      expect(fixture.host.servedCount, isZero);
    });
  });

  group('拉取备份', () {
    test('字节与导出结果逐字节相同', () async {
      final response = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(response.statusCode, HttpStatus.ok);
      expect(response.bodyBytes, testBackupBytes);
      expect(fixture.exportCalls, 1);
    });

    test('带上文件名与总行数响应头', () async {
      final response = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(
        response.headers.value(lanSyncBackupNameHeader),
        'lexiloop-backup-2026-10-16-101500.json',
      );
      expect(response.headers.value(lanSyncBackupRowsHeader), '1417');
    });

    test('成功一次后 servedCount 加一，并把累计次数回调出去', () async {
      final first = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(first.statusCode, HttpStatus.ok);
      final second = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(second.statusCode, HttpStatus.ok);
      expect(fixture.host.servedCount, 2);
      expect(fixture.exportCalls, 2);
      expect(fixture.servedCounts, <int>[1, 2]);
    });

    test('导出超过上限时返回 413 而不是 500', () async {
      fixture.failWith = const ValidationError(
        AppErrorCode.backupTooLarge,
        details: '导出结果 ${maxBackupBytes + 1} 字节',
      );
      final response = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(response.statusCode, lanSyncStatusTooLarge);
      final body = jsonDecode(response.body) as Map<String, Object?>;
      expect(body[lanSyncErrorCodeField], AppErrorCode.backupTooLarge.code);
      expect(fixture.host.servedCount, isZero);
    });

    test('导出抛其他业务错误时返回 500 并带上错误码', () async {
      fixture.failWith = const ValidationError(
        AppErrorCode.backupInvalidFormat,
      );
      final response = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(response.statusCode, HttpStatus.internalServerError);
      final body = jsonDecode(response.body) as Map<String, Object?>;
      expect(
        body[lanSyncErrorCodeField],
        AppErrorCode.backupInvalidFormat.code,
      );
    });

    test('导出抛未预期异常时返回 500，服务端继续可用', () async {
      fixture.unexpectedFailure = StateError('磁盘炸了');
      final failed = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(failed.statusCode, HttpStatus.internalServerError);

      // 关键断言：一次未预期异常不该让共享会话退出。
      fixture.unexpectedFailure = null;
      final ok = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(ok.statusCode, HttpStatus.ok);
    });

    test('同一时刻只服务一个请求，第二个得到 409', () async {
      fixture.delay = const Duration(milliseconds: 200);
      final first = fixture.get(lanSyncBackupPath, code: testCode);
      // 让第一个请求确实已经进入导出阶段。
      await Future<void>.delayed(const Duration(milliseconds: 60));
      final second = await fixture.get(lanSyncBackupPath, code: testCode);
      expect(second.statusCode, lanSyncStatusConflict);
      expect((await first).statusCode, HttpStatus.ok);
    });
  });

  group('其它请求', () {
    test('未知路径返回 404 与「对方已停止共享」', () async {
      final response = await fixture.get('/nope', code: testCode);
      expect(response.statusCode, lanSyncStatusNotFound);
      final body = jsonDecode(response.body) as Map<String, Object?>;
      expect(body[lanSyncErrorCodeField], AppErrorCode.lanSyncNotSharing.code);
    });

    test('非 GET 方法返回 405', () async {
      final response = await fixture.request(
        'POST',
        lanSyncBackupPath,
        code: testCode,
      );
      expect(response.statusCode, HttpStatus.methodNotAllowed);
    });
  });

  group('发现应答', () {
    test('收到本版本查询时单播回一条应答', () async {
      final reply = await fixture.queryDiscovery();
      expect(reply, isNotNull);

      final host = parseDiscoveredLanHost(reply, address: '127.0.0.1');
      expect(host, isNotNull);
      expect(host!.deviceName, '测试主机');
      expect(host.port, fixture.host.baseUri.port);
      expect(host.instanceId, fixture.instanceId);
    });

    test('收到的不是查询时报文时保持沉默', () async {
      final reply = await fixture.queryDiscovery(
        payload: <String, Object?>{'hello': 'world'},
      );
      expect(reply, isNull);
    });

    test('版本不一致的查询不应答', () async {
      final reply = await fixture.queryDiscovery(
        payload: <String, Object?>{
          ...lanSyncDiscoveryQueryWire(),
          'version': lanSyncProtocolVersion + 1,
        },
      );
      expect(reply, isNull);
    });
  });

  group('baseUri', () {
    test('用实际绑定到的端口，而不是请求的端口', () async {
      // 夹具传的是 0（由系统分配），因此这里能证明「报给对方的端口」是真实的。
      expect(fixture.host.baseUri.port, greaterThan(0));
      expect(fixture.host.baseUri.scheme, 'http');
    });
  });
}

/// 一个已启动的共享服务端与它的请求辅助方法。
class _HostFixture {
  /// 本次夹具的发现端口（启动时向系统要一个空闲的）。
  late final int discoveryPort;

  /// 固定的会话标识，便于断言。
  final String instanceId = 'fixture-instance';

  late final LanSyncHost host;
  int exportCalls = 0;
  int lockouts = 0;

  /// 服务端每次上报的累计服务次数。
  final List<int> servedCounts = <int>[];
  AppError? failWith;

  /// 非 `AppError` 的意外异常，用来验证「未预期异常不外泄」。
  Error? unexpectedFailure;
  Duration? delay;

  /// 启动服务端（TCP 与发现端口都交给系统分配）。
  Future<void> start() async {
    discoveryPort = await freeUdpPort();
    host = await createLanSyncHost(
      LanSyncHostOptions(
        deviceName: '测试主机',
        port: 0,
        pairingCode: testCode,
        instanceId: instanceId,
        discoveryPort: discoveryPort,
        backupSource: _export,
        onCodeLockout: () => lockouts += 1,
        onServed: servedCounts.add,
      ),
    );
  }

  /// 关掉服务端。
  Future<void> dispose() => host.stop();

  Future<LanSyncBackup> _export() async {
    exportCalls += 1;
    final delay = this.delay;
    if (delay != null) await Future<void>.delayed(delay);
    final unexpected = unexpectedFailure;
    if (unexpected != null) throw unexpected;
    final failure = failWith;
    if (failure != null) throw failure;
    return LanSyncBackup(
      bytes: testBackupBytes,
      fileName: 'lexiloop-backup-2026-10-16-101500.json',
      totalRows: 1417,
    );
  }

  /// 发一个请求并读回完整响应。
  Future<_TestResponse> get(String path, {String? code}) =>
      request('GET', path, code: code);

  /// 以任意方法发一个请求。
  Future<_TestResponse> request(
    String method,
    String path, {
    String? code,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, host.baseUri.resolve(path));
      if (code != null) request.headers.set(lanSyncCodeHeader, code);
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        <int>[],
        (accumulated, chunk) => accumulated..addAll(chunk),
      );
      return _TestResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        bodyBytes: Uint8List.fromList(bytes),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// 广播一次查询并等应答；超时未收到返回 `null`。
  Future<Object?> queryDiscovery({Object? payload}) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0)
      ..broadcastEnabled = true;
    try {
      final data = utf8.encode(
        jsonEncode(payload ?? lanSyncDiscoveryQueryWire()),
      );
      socket.send(data, InternetAddress.loopbackIPv4, discoveryPort);

      final completer = Completer<Object?>();
      final subscription = socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;
        if (!completer.isCompleted) {
          completer.complete(jsonDecode(utf8.decode(datagram.data)));
        }
      });
      final result = await completer.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      await subscription.cancel();
      return result;
    } finally {
      socket.close();
    }
  }
}

/// 一次响应。
class _TestResponse {
  /// 以状态码、响应头与响应体构造。
  const new({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });

  /// 状态码。
  final int statusCode;

  /// 响应头。
  final HttpHeaders headers;

  /// 响应体字节。
  final Uint8List bodyBytes;

  /// 响应体文本。
  String get body => utf8.decode(bodyBytes);
}
