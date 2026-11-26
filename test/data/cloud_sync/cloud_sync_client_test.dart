import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/constants.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_client_dio.dart';
import 'package:lexiloop/data/cloud_sync/cloud_sync_protocol.dart';
import 'package:lexiloop/domain/models/cloud_sync_settings.dart';
import 'package:lexiloop/domain/sync/delta_batch_splitter.dart';

class _StubAdapter implements HttpClientAdapter {
  new(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;
  RequestOptions? lastOptions;
  List<int>? lastBodyBytes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastOptions = options;
    if (requestStream != null) {
      final chunks = await requestStream.toList();
      lastBodyBytes = chunks.expand((c) => c).toList();
    }
    return await _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(
  Object body, {
  int statusCode = 200,
  bool gzipped = false,
}) {
  final raw = utf8.encode(jsonEncode(body));
  final bytes = gzipped ? gzip.encode(raw) : raw;
  return ResponseBody.fromBytes(
    bytes,
    statusCode,
    headers: <String, List<String>>{
      'content-type': <String>['application/json'],
      if (gzipped) 'content-encoding': <String>['gzip'],
    },
  );
}

void main() {
  const credential = CloudSyncCredential(
    baseUrl: 'https://lexiloop.vercel.app/',
    password: 'my-password',
  );

  test('handshake sends password header and parses server info', () async {
    final adapter = _StubAdapter(
      (_) async => _jsonResponse(<String, Object?>{
        'success': true,
        'data': <String, Object?>{
          'service': cloudSyncServiceName,
          'protocolVersion': cloudSyncProtocolVersion,
          'deviceId': 'srv-01',
          'datasetEpoch': 'ep-01',
          'serverNow': 1730000000000,
          'wordCount': 42,
          'pushSince': 1729999000000,
        },
      }),
    );
    final dio = Dio()..httpClientAdapter = adapter;
    final client = CloudSyncHttpClient(credential, dio: dio);

    final reply = await client.handshake(
      const CloudSyncHandshakeRequest(
        deviceId: 'cli-01',
        deviceName: 'Mac',
        datasetEpoch: 'cli-ep',
      ),
    );

    expect(
      adapter.lastOptions?.uri.toString(),
      'https://lexiloop.vercel.app/api/sync/handshake',
    );
    expect(
      adapter.lastOptions?.headers[cloudSyncPasswordHeader],
      'my-password',
    );
    expect(reply.deviceId, 'srv-01');
    expect(reply.wordCount, 42);
    expect(reply.pushSince, 1729999000000);
  });

  test(
    'pushBatch compresses request body with GZip and parses gzip response',
    () async {
      final adapter = _StubAdapter(
        (_) async => _jsonResponse(<String, Object?>{
          'success': true,
          'data': <String, Object?>{
            'summary': <String, Object?>{
              'addedWords': 1,
              'updatedWords': 0,
              'addedLogs': 2,
              'rebuiltWords': 1,
              'wordCount': 10,
            },
            'datasetEpoch': 'ep-02',
            'serverNow': 1730000005000,
          },
        }, gzipped: true),
      );
      final dio = Dio()..httpClientAdapter = adapter;
      final client = CloudSyncHttpClient(credential, dio: dio);

      final reply = await client.pushBatch(
        const CloudSyncPushRequest(
          batch: CloudSyncPushBatch(
            tables: <String, List<Map<String, Object?>>>{
              'words': <Map<String, Object?>>[
                <String, Object?>{'id': 1, 'term': 'apple'},
              ],
            },
          ),
          meta: CloudSyncPushMeta(
            clientDeviceId: 'cli-01',
            clientDeviceName: 'Mac',
            clientDatasetEpoch: 'cli-ep',
            clientServerNow: 1730000000000,
          ),
          commitWatermark: true,
        ),
      );

      expect(adapter.lastOptions?.headers['Content-Encoding'], 'gzip');
      expect(adapter.lastBodyBytes, isNotNull);
      final decompressed = utf8.decode(gzip.decode(adapter.lastBodyBytes!));
      expect(jsonDecode(decompressed), isA<Map<String, Object?>>());
      expect(reply.summary.addedWords, 1);
      expect(reply.summary.addedLogs, 2);
      expect(reply.datasetEpoch, 'ep-02');
    },
  );

  test('maps 401 and 413 responses to typed AppErrorCode', () async {
    final dio401 = Dio()
      ..httpClientAdapter = _StubAdapter(
        (_) async => _jsonResponse(<String, Object?>{
          'success': false,
          'error': <String, Object?>{'code': 'AUTH_REQUIRED'},
        }, statusCode: 401),
      );
    final client401 = CloudSyncHttpClient(credential, dio: dio401);
    await expectLater(
      () => client401.handshake(
        const CloudSyncHandshakeRequest(
          deviceId: 'c',
          deviceName: 'M',
          datasetEpoch: 'e',
        ),
      ),
      throwsA(
        isA<AppError>().having(
          (e) => e.code,
          'code',
          AppErrorCode.cloudSyncAuthFailed,
        ),
      ),
    );

    final dio413 = Dio()
      ..httpClientAdapter = _StubAdapter(
        (_) async => _jsonResponse(<String, Object?>{
          'success': false,
          'error': <String, Object?>{'code': 'SYNC_PAYLOAD_TOO_LARGE'},
        }, statusCode: 413),
      );
    final client413 = CloudSyncHttpClient(credential, dio: dio413);
    await expectLater(
      () => client413.pullPage(const CloudSyncPullRequest(mode: 'delta')),
      throwsA(
        isA<AppError>().having(
          (e) => e.code,
          'code',
          AppErrorCode.cloudSyncPayloadTooLarge,
        ),
      ),
    );
  });

  test('pre-cancelled signal aborts before sending HTTP request', () async {
    final dio = Dio()
      ..httpClientAdapter = _StubAdapter((_) async => throw StateError('hit'));
    final client = CloudSyncHttpClient(credential, dio: dio);
    final signal = CloudSyncCancelSignal()..cancel();

    await expectLater(
      () => client.handshake(
        const CloudSyncHandshakeRequest(
          deviceId: 'c',
          deviceName: 'M',
          datasetEpoch: 'e',
        ),
        cancelSignal: signal,
      ),
      throwsA(
        isA<AppError>().having(
          (e) => e.code,
          'code',
          AppErrorCode.cloudSyncCancelled,
        ),
      ),
    );
  });
}
