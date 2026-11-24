/// 词书包多通道下载器、SHA-256 校验、自动降级与备份合并测试。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/word_packs/word_pack_downloader.dart';
import 'package:lexiloop/domain/models/word_pack_models.dart';
import 'package:lexiloop/services/fsrs_scheduler.dart';
import 'package:lexiloop/services/merge/backup_merge.dart';

class _FakeHttpPort implements WordPackHttpPort {
  new(this.responses);

  final Map<String, Object> responses;
  final List<String> requestedUrls = <String>[];

  @override
  Future<Uint8List> getBytes(
    String url, {
    required int timeoutMs,
    WordPackProgressCallback? onProgress,
    WordPackCancelSignal? cancel,
  }) async {
    requestedUrls.add(url);
    final response = responses[url];
    if (response is Uint8List) {
      onProgress?.call(response.length, response.length);
      return response;
    }
    if (response is AppError) throw response;
    throw const ExternalServiceError(
      AppErrorCode.wordPackDownloadFailed,
      isTransient: true,
    );
  }

  @override
  Future<int?> probeLatency(String url, {required int timeoutMs}) async => 100;
}

void main() {
  group('URL 路由与多通道降级', () {
    test('智能优选通道按国内加速优先、GitHub 直连兜底顺序生成 URL', () {
      const config = WordPackDownloadConfig();
      final urls = resolveWordPackUrls(
        config: config,
        relativePath: 'packs/cet4.lexipack.json.gz',
      );
      expect(urls.first, contains('gcore.jsdelivr.net'));
      expect(urls[1], contains('ghfast.top'));
      expect(urls[2], contains('gh-proxy.com'));
      expect(urls.last, startsWith('https://raw.githubusercontent.com/'));
    });

    test('自定义代理模板支持 {url} 与基础前缀两种形式', () {
      const proxyTemplate = WordPackDownloadConfig(
        channel: WordPackChannelKind.custom,
        customBaseUrl: 'https://cf.example.com/proxy?u={url}',
      );
      final templated = resolveWordPackUrls(
        config: proxyTemplate,
        relativePath: 'packs/ielts.lexipack.json.gz',
      );
      expect(
        templated.single,
        startsWith(
          'https://cf.example.com/proxy?u=https://raw.githubusercontent.com/',
        ),
      );

      const staticHost = WordPackDownloadConfig(
        channel: WordPackChannelKind.custom,
        customBaseUrl: 'https://cdn.example.com/wordbooks',
      );
      final hosted = resolveWordPackUrls(
        config: staticHost,
        relativePath: 'packs/ielts.lexipack.json.gz',
      );
      expect(
        hosted.single,
        'https://cdn.example.com/wordbooks/packs/ielts.lexipack.json.gz',
      );
    });

    test('前序加速通道失败时自动回退并校验 SHA-256', () async {
      final payloadBytes = Uint8List.fromList(utf8.encode('{"ok":true}'));
      final expectedHash = sha256.convert(payloadBytes).toString();
      const item = WordPackCatalogItem(
        id: 'cet4',
        slug: 'cet4',
        name: '四级',
        category: WordPackCategory.examCn,
        description: '',
        version: '2026.1',
        contentMode: WordPackContentMode.ecdictBase,
        wordCount: 1,
        compressedBytes: 11,
        sha256: '',
        relativePath: 'packs/cet4.lexipack.json.gz',
      );
      final strictItem = WordPackCatalogItem(
        id: item.id,
        slug: item.slug,
        name: item.name,
        category: item.category,
        description: item.description,
        version: item.version,
        contentMode: item.contentMode,
        wordCount: item.wordCount,
        compressedBytes: item.compressedBytes,
        sha256: expectedHash,
        relativePath: item.relativePath,
      );

      const config = WordPackDownloadConfig();
      final urls = resolveWordPackUrls(
        config: config,
        relativePath: strictItem.relativePath,
      );
      final fake = _FakeHttpPort(<String, Object>{
        // 第一个镜像返回被篡改内容（校验应失败并回退下一个）
        urls[0]: Uint8List.fromList(utf8.encode('corrupted')),
        // 第二个镜像超时失败
        urls[1]: const ExternalServiceError(
          AppErrorCode.wordPackDownloadFailed,
          isTransient: true,
        ),
        // 第三个镜像返回正确字节
        urls[2]: payloadBytes,
      });

      final downloader = WordPackDownloader(fake);
      final res = await downloader.downloadPack(
        item: strictItem,
        config: config,
      );
      expect(res.sha256Hex, expectedHash);
      expect(res.resolvedUrl, urls[2]);
      expect(fake.requestedUrls, hasLength(3));
    });

    test('所有通道校验和均不匹配时抛出 wordPackChecksumMismatch', () async {
      const config = WordPackDownloadConfig(
        channel: WordPackChannelKind.githubDirect,
      );
      const item = WordPackCatalogItem(
        id: 'cet4',
        slug: 'cet4',
        name: '四级',
        category: WordPackCategory.examCn,
        description: '',
        version: '2026.1',
        contentMode: WordPackContentMode.ecdictBase,
        wordCount: 1,
        compressedBytes: 5,
        sha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
        relativePath: 'packs/cet4.lexipack.json.gz',
      );
      final url = resolveWordPackUrls(
        config: config,
        relativePath: item.relativePath,
      ).single;
      final downloader = WordPackDownloader(
        _FakeHttpPort(<String, Object>{
          url: Uint8List.fromList(utf8.encode('tampered')),
        }),
      );

      await expectLater(
        downloader.downloadPack(item: item, config: config),
        throwsA(
          isA<ValidationError>().having(
            (e) => e.code,
            'code',
            AppErrorCode.wordPackChecksumMismatch,
          ),
        ),
      );
    });
  });

  group('备份合并兼容', () {
    test('mergeBackupTables 对 is_personal 做逻辑或升格，并合并词书表与关联表', () {
      final local = <String, List<Map<String, Object?>>>{
        'words': <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'term': 'abandon',
            'normalized_term': 'abandon',
            'source_language': 'en',
            'target_language': 'zh',
            'is_personal': 0,
            'updated_at': 100,
          },
        ],
        'word_packs': <Map<String, Object?>>[],
        'word_pack_items': <Map<String, Object?>>[],
      };
      final remote = <String, List<Map<String, Object?>>>{
        'words': <Map<String, Object?>>[
          <String, Object?>{
            'id': 9,
            'term': 'abandon',
            'normalized_term': 'abandon',
            'source_language': 'en',
            'target_language': 'zh',
            'is_personal': 1,
            'updated_at': 200,
          },
        ],
        'word_packs': <Map<String, Object?>>[
          <String, Object?>{
            'id': 'cet4',
            'slug': 'cet4',
            'name': '四级',
            'version': '2026.1',
            'installed_at': 150,
            'updated_at': 200,
          },
        ],
        'word_pack_items': <Map<String, Object?>>[
          <String, Object?>{'pack_id': 'cet4', 'word_id': 9, 'rank': 1},
        ],
      };

      final merged = mergeBackupTables(
        local: local,
        remote: remote,
        scheduler: FsrsScheduler(),
        now: 300,
      );
      expect(merged.tables['words']!.single['is_personal'], 1);
      expect(merged.tables['word_packs'], hasLength(1));
      expect(merged.tables['word_pack_items']!.single['word_id'], 1);
    });
  });
}
