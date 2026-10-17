/// `WebdavClient` 的协议级测试。
///
/// 被测的是「我们按 WebDAV 说了什么话」：方法、路径（目录有没有补斜杠）、
/// 认证头、请求体、`Depth`，以及各种状态码映射成哪个业务错误。
/// 传输层被 [RecordingDioAdapter] 换掉，因此全部离线运行。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/remote_backup/remote_backup_entry.dart';
import 'package:lexiloop/data/remote_backup/webdav_client.dart';
import 'package:lexiloop/domain/models/webdav_settings.dart';

import '../../support/recording_dio_adapter.dart';

/// 备份目录的 PROPFIND 响应（含目录自身与一份备份）。
const String _listingXml =
    '<d:multistatus xmlns:d="DAV:">'
    ' <d:response><d:href>/dav/LexiLoop/</d:href><d:propstat><d:prop>'
    ' <d:resourcetype><d:collection/></d:resourcetype>'
    ' </d:prop></d:propstat></d:response>'
    ' <d:response>'
    ' <d:href>/dav/LexiLoop/lexiloop-backup-2026-10-16-101500.json</d:href>'
    ' <d:propstat><d:prop><d:resourcetype/>'
    ' <d:getcontentlength>12</d:getcontentlength>'
    ' <d:getlastmodified>Fri, 16 Oct 2026 10:15:00 GMT</d:getlastmodified>'
    ' </d:prop></d:propstat></d:response>'
    ' </d:multistatus>';

void main() {
  WebdavCredential credential({String directory = 'LexiLoop'}) =>
      WebdavCredential(
        baseUrl: 'https://dav.example.com/dav',
        directory: normalizeWebdavDirectory(directory),
        username: 'leo',
        password: 'app-pass',
      );

  (WebdavClient, RecordingDioAdapter) build(
    List<ScriptedResponse> responses, {
    String directory = 'LexiLoop',
  }) {
    final adapter = RecordingDioAdapter(responses);
    final client = WebdavClient(
      credential(directory: directory),
      dio: dioWith(adapter),
    );
    return (client, adapter);
  }

  group('认证', () {
    test('每个请求都带 HTTP Basic 认证头', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 207, body: _listingXml),
      ]);

      await client.listBackups();

      final expected = 'Basic ${base64Encode(utf8.encode('leo:app-pass'))}';
      expect(adapter.last.header('authorization'), expected);
    });
  });

  group('建目录', () {
    test('目录已存在时只发一次 PROPFIND', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 207, body: _listingXml),
      ]);

      await client.ensureDirectory();

      expect(adapter.requests, hasLength(1));
      expect(adapter.last.method, 'PROPFIND');
      expect(
        adapter.last.uri.toString(),
        'https://dav.example.com/dav/LexiLoop/',
      );
      expect(adapter.last.header('depth'), '0');
    });

    test('目录不存在时逐级 MKCOL', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 404),
        const ScriptedResponse(statusCode: 201),
        const ScriptedResponse(statusCode: 201),
      ], directory: 'a/b');

      await client.ensureDirectory();

      expect(adapter.requests.map((request) => request.method), <String>[
        'PROPFIND',
        'MKCOL',
        'MKCOL',
      ]);
      expect(
        adapter.requests.map((request) => request.uri.toString()),
        <String>[
          'https://dav.example.com/dav/a/b/',
          'https://dav.example.com/dav/a/',
          'https://dav.example.com/dav/a/b/',
        ],
      );
    });

    test('MKCOL 返回 405（已存在）不算失败', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 404),
        const ScriptedResponse(statusCode: 405),
      ]);

      await expectLater(client.ensureDirectory(), completes);
      expect(adapter.requests.last.method, 'MKCOL');
    });

    test('401 映射成鉴权失败，且不再尝试建目录', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 401),
      ]);

      await expectLater(
        client.ensureDirectory(),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.webdavAuthFailed,
          ),
        ),
      );
      expect(adapter.requests, hasLength(1));
    });
  });

  group('上传', () {
    test('PUT 到目录内的文件名，带上 JSON 的内容类型与长度', () async {
      final bytes = Uint8List.fromList(utf8.encode('{"format":"x"}'));
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 201),
      ]);

      await client.putBackup(fileName: 'lexiloop-backup-x.json', bytes: bytes);

      expect(adapter.last.method, 'PUT');
      expect(
        adapter.last.uri.toString(),
        'https://dav.example.com/dav/LexiLoop/lexiloop-backup-x.json',
      );
      expect(adapter.last.header('content-type'), 'application/json');
      expect(adapter.last.header('content-length'), '${bytes.length}');
      expect(adapter.last.body, bytes);
    });

    test('507（空间不足）映射成可重试的请求失败', () async {
      final (client, _) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 507),
      ]);

      await expectLater(
        client.putBackup(
          fileName: 'lexiloop-backup-x.json',
          bytes: Uint8List.fromList(<int>[1]),
        ),
        throwsA(
          isA<ExternalServiceError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.webdavRequestFailed,
              )
              .having((error) => error.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('403 映射成鉴权失败且不可重试', () async {
      final (client, _) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 403),
      ]);

      await expectLater(
        client.putBackup(
          fileName: 'lexiloop-backup-x.json',
          bytes: Uint8List.fromList(<int>[1]),
        ),
        throwsA(
          isA<ExternalServiceError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.webdavAuthFailed,
              )
              .having((error) => error.isTransient, 'isTransient', isFalse),
        ),
      );
    });
  });

  group('列出与下载', () {
    test('PROPFIND 用 Depth: 1 并解析出备份', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 207, body: _listingXml),
      ]);

      final entries = await client.listBackups();

      expect(adapter.last.method, 'PROPFIND');
      expect(adapter.last.header('depth'), '1');
      expect(entries.single.name, 'lexiloop-backup-2026-10-16-101500.json');
    });

    test('目录不存在（404）映射成 notFound', () async {
      final (client, _) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 404),
      ]);

      await expectLater(
        client.listBackups(),
        throwsA(
          isA<NotFoundError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.webdavNotFound,
          ),
        ),
      );
    });

    test('下载按字节取回，且请求的是条目自己的 URL', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 200, body: '{"format":"lexiloop"}'),
      ]);
      const entry = RemoteBackupEntry(
        name: 'lexiloop-backup-2026-10-16-101500.json',
        sizeBytes: 20,
      );

      final bytes = await client.downloadBackup(entry);

      expect(utf8.decode(bytes), '{"format":"lexiloop"}');
      expect(
        adapter.last.uri.toString(),
        'https://dav.example.com/dav/LexiLoop/lexiloop-backup-2026-10-16-101500.json',
      );
    });

    test('声明超过上限的条目在下载前就被拒绝', () async {
      final (client, adapter) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 200, body: '{}'),
      ]);

      await expectLater(
        client.downloadBackup(
          const RemoteBackupEntry(
            name: 'lexiloop-backup-x.json',
            sizeBytes: 1 << 40,
          ),
        ),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupTooLarge,
          ),
        ),
      );
      expect(adapter.requests, isEmpty, reason: '不该为一个明显过大的条目发请求');
    });

    test('空响应体视为备份格式错误', () async {
      final (client, _) = build(<ScriptedResponse>[
        const ScriptedResponse(statusCode: 200),
      ]);

      await expectLater(
        client.downloadBackup(
          const RemoteBackupEntry(name: 'lexiloop-backup-x.json', sizeBytes: 0),
        ),
        throwsA(
          isA<ValidationError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.backupInvalidFormat,
          ),
        ),
      );
    });
  });

  group('传输层失败', () {
    test('连不上映射成 webdavUnreachable（可重试）', () async {
      final (client, _) = build(<ScriptedResponse>[
        const ScriptedResponse(
          statusCode: 0,
          failure: DioExceptionType.connectionError,
        ),
      ]);

      await expectLater(
        client.listBackups(),
        throwsA(
          isA<ExternalServiceError>()
              .having(
                (error) => error.code,
                'code',
                AppErrorCode.webdavUnreachable,
              )
              .having((error) => error.isTransient, 'isTransient', isTrue),
        ),
      );
    });

    test('请求超时同样归成 webdavUnreachable', () async {
      final (client, _) = build(<ScriptedResponse>[
        const ScriptedResponse(
          statusCode: 0,
          failure: DioExceptionType.connectionTimeout,
        ),
      ]);

      await expectLater(
        client.listBackups(),
        throwsA(
          isA<ExternalServiceError>().having(
            (error) => error.code,
            'code',
            AppErrorCode.webdavUnreachable,
          ),
        ),
      );
    });
  });
}
