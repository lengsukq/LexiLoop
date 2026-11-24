/// 词书包中心页面 Widget 测试。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/core/errors.dart';
import 'package:lexiloop/data/db/dao_providers.dart';
import 'package:lexiloop/data/db/database.dart';
import 'package:lexiloop/data/db/database_provider.dart';
import 'package:lexiloop/data/word_packs/pack_gzip.dart';
import 'package:lexiloop/data/word_packs/word_pack_downloader.dart';
import 'package:lexiloop/features/packs/word_packs_page.dart';
import 'package:lexiloop/features/packs/word_packs_providers.dart';
import 'package:lexiloop/ui/theme/lexi_theme.dart';

class _MemoryPackHttpPort implements WordPackHttpPort {
  new(this.packBytes);

  final Uint8List packBytes;

  @override
  Future<Uint8List> getBytes(
    String url, {
    required int timeoutMs,
    WordPackProgressCallback? onProgress,
    WordPackCancelSignal? cancel,
  }) async {
    if (url.endsWith('catalog.json')) {
      throw const ExternalServiceError(
        AppErrorCode.wordPackDownloadFailed,
        isTransient: true,
      );
    }
    onProgress?.call(packBytes.length, packBytes.length);
    return packBytes;
  }

  @override
  Future<int?> probeLatency(String url, {required int timeoutMs}) async => 120;
}

void main() {
  testWidgets('词书包中心支持目录展示、通道设置、下载安装与安全卸载', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final packBytes = encodeWordPackGzip(
      jsonEncode(<String, Object?>{
        'format': 'lexiloop-wordbook-pack',
        'formatVersion': 1,
        'pack': <String, Object?>{
          'id': 'cet4',
          'slug': 'cet4',
          'name': '大学英语四级 (CET-4)',
          'category': 'EXAM_CN',
          'description': '四级核心词表',
          'version': '2026.1',
          'contentMode': 'ECDICT_BASE',
        },
        'entries': <Map<String, Object?>>[
          <String, Object?>{
            'term': 'abandon',
            'rank': 1,
            'definitions': <Map<String, Object?>>[
              <String, Object?>{
                'language': 'zh',
                'partOfSpeech': 'v',
                'text': '放弃',
                'source': 'ecdict',
              },
            ],
          },
        ],
      }),
    );
    final shaHex = sha256.convert(packBytes).toString();
    final bundledCatalog = jsonEncode(<String, Object?>{
      'format': 'lexiloop-wordbook-catalog',
      'version': 1,
      'repo': 'lengsukq/LexiLoop-packs',
      'ref': 'v1.0.0',
      'updatedAt': '2026-11-24T00:00:00Z',
      'packs': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'cet4',
          'slug': 'cet4',
          'name': '大学英语四级 (CET-4)',
          'category': 'EXAM_CN',
          'description': '四级核心词表',
          'version': '2026.1',
          'contentMode': 'ECDICT_BASE',
          'wordCount': 1,
          'compressedBytes': packBytes.length,
          'sha256': shaHex,
          'relativePath': 'packs/cet4.lexipack.json.gz',
        },
      ],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          wordPackHttpPortProvider.overrideWithValue(
            _MemoryPackHttpPort(packBytes),
          ),
          bundledWordPackCatalogLoaderProvider.overrideWithValue(
            () async => bundledCatalog,
          ),
        ],
        child: MaterialApp(theme: LexiTheme.light, home: const WordPacksPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('大学英语四级 (CET-4)'), findsOneWidget);
    expect(find.text('内置离线目录'), findsOneWidget);

    // 打开通道切换面板并测速。
    await tester.tap(find.text('切换通道 / 测速'));
    await tester.pumpAndSettle();
    expect(find.text('词书下载通道'), findsOneWidget);
    await tester.tap(find.text('一键测速'));
    await tester.pumpAndSettle();
    expect(find.text('120ms'), findsWidgets);
    await tester.tap(find.text('保存通道设置'));
    await tester.pumpAndSettle();

    // 下载并添加四级词书。
    await tester.tap(find.text('下载并添加'));
    await tester.pumpAndSettle();
    expect(find.text('添加「大学英语四级 (CET-4)」'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '下载并添加'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已添加'), findsOneWidget);
    expect(find.text('专项学习'), findsOneWidget);
    expect(find.text('纳入每日学习计划'), findsOneWidget);
  });
}
