/// 局域网对端客户端的测试。
///
/// 替换 `dio` 的传输层而不是在端口层造假：本文件的正确性有一半在
/// 「我们到底发了什么请求」——方法、路径（相对目标设备的根地址）、
/// 配对码请求头。另一半是状态码到业务错误码的映射。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_client_dio.dart';
import 'package:lexiloop/data/lan_sync/lan_sync_protocol.dart';
import 'package:lexiloop/domain/models/lan_sync_settings.dart';

import '../../support/recording_dio_adapter.dart';

/// 测试目标设备。
const DiscoveredLanHost targetHost = DiscoveredLanHost(
  instanceId: 'peer-1',
  deviceName: 'LexiLoop 手机',
  address: '192.168.1.7',
  port: 8765,
  protocolVersion: lanSyncProtocolVersion,
);

/// 测试用配对码。
const String code = '135790';

/// 一份合法的握手响应体。
String handshakeBody({
  int version = lanSyncProtocolVersion,
  String device = 'LexiLoop 手机',
  String service = lanSyncServiceName,
}) => jsonEncode(<String, Object?>{
  lanSyncHandshakeServiceField: service,
  lanSyncHandshakeVersionField: version,
  lanSyncHandshakeDeviceField: device,
});

/// 备份的字节。
final Uint8List backupBytes = Uint8List.fromList(
  utf8.encode('{"format":"lexiloop-json-backup","version":3}'),
);

void main() {
  late RecordingDioAdapter adapter;

  LanSyncHttpClient clientWith(
    List<ScriptedResponse> responses, {
    DiscoveredLanHost host = targetHost,
  }) {
    adapter = RecordingDioAdapter(responses);
    return LanSyncHttpClient(host, code, dio: dioWith(adapter));
  }

  group('handshake', () {
    test('GET 到握手路径，并带上配对码请求头', () async {
      final client = clientWith(<ScriptedResponse>[
        ScriptedResponse(statusCode: 200, body: handshakeBody()),
      ]);
      final handshake = await client.handshake();

      expect(adapter.last.method, 'GET');
      expect(
        adapter.last.uri.toString(),
        'http://192.168.1.7:8765$lanSyncHandshakePath',
      );
      expect(adapter.last.header(lanSyncCodeHeader), code);
      expect(handshake.deviceName, 'LexiLoop 手机');
      expect(handshake.protocolVersion, lanSyncProtocolVersion);
    });

    test('401 映射成「配对码不正确」', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: lanSyncStatusUnauthorized),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncCodeInvalid,
          ),
        ),
      );
    });

    test('404 映射成「对方已停止共享」', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: lanSyncStatusNotFound),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<NotFoundError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncNotSharing,
          ),
        ),
      );
    });

    test('409 映射成「对方正在同步中」且可重试', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: lanSyncStatusConflict),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>()
              .having((error) => error.code, 'code', AppErrorCode.lanSyncBusy)
              .having((error) => error.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('500 映射成「请求失败」且标记为可重试', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 500),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.lanSyncRequestFailed,
              )
              .having((error) => error.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('400 映射成「请求失败」但不可重试', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 400),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.lanSyncRequestFailed,
              )
              .having((error) => error.isTransient, 'isTransient', isFalse),
        ),
      );
    });

    test('版本不一致时报「版本不兼容」而不是「码错」', () async {
      final client = clientWith(<ScriptedResponse>[
        ScriptedResponse(
          statusCode: 200,
          body: handshakeBody(version: lanSyncProtocolVersion + 1),
        ),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncProtocolMismatch,
          ),
        ),
      );
    });

    test('响应不是本协议时报「对方已停止共享」', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 200, body: '<html>nginx</html>'),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncNotSharing,
          ),
        ),
      );
    });

    test('服务标识不符时报「对方已停止共享」', () async {
      final client = clientWith(<ScriptedResponse>[
        ScriptedResponse(
          statusCode: 200,
          body: handshakeBody(service: 'something-else'),
        ),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncNotSharing,
          ),
        ),
      );
    });

    test('连不上时映射成「无法连接该设备」且可重试', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(
          statusCode: 0,
          failure: DioExceptionType.connectionError,
        ),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.lanSyncUnreachable,
              )
              .having((error) => error.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('超时同样映射成「无法连接该设备」', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(
          statusCode: 0,
          failure: DioExceptionType.receiveTimeout,
        ),
      ]);
      await expectLater(
        client.handshake(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncUnreachable,
          ),
        ),
      );
    });
  });

  group('downloadBackup', () {
    ScriptedResponse backupResponse({
      Map<String, String> headers = const <String, String>{
        lanSyncBackupNameHeader: 'lexiloop-backup-2026-10-16-101500.json',
        lanSyncBackupRowsHeader: '1417',
      },
    }) => ScriptedResponse(
      statusCode: 200,
      body: utf8.decode(backupBytes),
      headers: headers,
    );

    test('GET 到备份路径并带上配对码请求头', () async {
      final client = clientWith(<ScriptedResponse>[backupResponse()]);
      final backup = await client.downloadBackup();

      expect(adapter.last.method, 'GET');
      expect(
        adapter.last.uri.toString(),
        'http://192.168.1.7:8765$lanSyncBackupPath',
      );
      expect(adapter.last.header(lanSyncCodeHeader), code);
      expect(backup.bytes, backupBytes);
    });

    test('读出文件名与总行数响应头', () async {
      final client = clientWith(<ScriptedResponse>[backupResponse()]);
      final backup = await client.downloadBackup();
      expect(backup.fileName, 'lexiloop-backup-2026-10-16-101500.json');
      expect(backup.totalRows, 1417);
    });

    test('响应头缺失时文件名退化为空串、行数为 0', () async {
      final client = clientWith(<ScriptedResponse>[
        backupResponse(headers: const <String, String>{}),
      ]);
      final backup = await client.downloadBackup();
      expect(backup.fileName, isEmpty);
      expect(backup.totalRows, isZero);
    });

    test('空响应体按「备份格式无效」拒绝', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 200),
      ]);
      await expectLater(
        client.downloadBackup(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupInvalidFormat,
          ),
        ),
      );
    });

    test('413 映射成「备份文件过大」而不是通用失败', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: lanSyncStatusTooLarge),
      ]);
      await expectLater(
        client.downloadBackup(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupTooLarge,
          ),
        ),
      );
    });

    test('401 映射成「配对码不正确」', () async {
      final client = clientWith(<ScriptedResponse>[
        const ScriptedResponse(statusCode: lanSyncStatusUnauthorized),
      ]);
      await expectLater(
        client.downloadBackup(),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.lanSyncCodeInvalid,
          ),
        ),
      );
    });
  });

  group('目标地址', () {
    test('按目标设备的地址与端口拼路径，不依赖服务端自报的地址', () async {
      const other = DiscoveredLanHost(
        instanceId: 'peer-2',
        deviceName: '',
        address: '10.1.2.3',
        port: 9001,
        protocolVersion: lanSyncProtocolVersion,
      );
      final client = clientWith(<ScriptedResponse>[
        ScriptedResponse(statusCode: 200, body: handshakeBody()),
      ], host: other);
      await client.handshake();
      expect(
        adapter.last.uri.toString(),
        'http://10.1.2.3:9001$lanSyncHandshakePath',
      );
    });
  });
}
