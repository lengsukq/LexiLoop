/// 原生磁盘离线语音缓存单测（基于真实临时目录验证读写、原子写、统计与 LRU 淘汰）。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';
import 'package:lexiloop/services/audio/speech_disk_cache_native.dart';

void main() {
  late Directory tempDir;
  late NativeSpeechDiskCache cache;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lexiloop_speech_cache_');
    cache = NativeSpeechDiskCache(rootDirectoryProvider: () async => tempDir);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('支持分桶写入、读取、存在检查与无残留 .tmp 原子落盘', () async {
    final youdaoBytes = Uint8List.fromList(List<int>.filled(128, 7));
    final edgeBytes = Uint8List.fromList(List<int>.filled(256, 9));

    await cache.write(SpeechCacheBucket.youdao, 'u:apple', youdaoBytes);
    await cache.write(SpeechCacheBucket.edge, 'US:hello', edgeBytes);

    expect(await cache.contains(SpeechCacheBucket.youdao, 'u:apple'), isTrue);
    expect(
      await cache.contains(SpeechCacheBucket.youdao, 'u:missing'),
      isFalse,
    );
    expect(await cache.read(SpeechCacheBucket.youdao, 'u:apple'), youdaoBytes);
    expect(await cache.read(SpeechCacheBucket.edge, 'US:hello'), edgeBytes);

    final stats = await cache.stats();
    expect(stats.youdaoFiles, 1);
    expect(stats.youdaoBytes, 128);
    expect(stats.edgeFiles, 1);
    expect(stats.edgeBytes, 256);
    expect(stats.totalFiles, 2);
    expect(stats.totalBytes, 384);

    // 确认原子写入没有遗留 .tmp 文件。
    final allFiles = tempDir.listSync(recursive: true).whereType<File>();
    expect(allFiles.where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('分桶清理互不干扰，全清归零', () async {
    await cache.write(
      SpeechCacheBucket.youdao,
      'k1',
      Uint8List.fromList(<int>[1, 2, 3]),
    );
    await cache.write(
      SpeechCacheBucket.edge,
      'k2',
      Uint8List.fromList(<int>[4, 5, 6, 7]),
    );

    await cache.clear(bucket: SpeechCacheBucket.youdao);
    final afterYoudao = await cache.stats();
    expect(afterYoudao.youdaoFiles, 0);
    expect(afterYoudao.edgeFiles, 1);

    await cache.clear();
    final afterAll = await cache.stats();
    expect(afterAll.totalFiles, 0);
    expect(afterAll.totalBytes, 0);
  });

  test('超限时按最后修改时间淘汰最久未用文件并压回 85% 水位', () async {
    final payload = Uint8List.fromList(List<int>.filled(100, 1));
    await cache.write(SpeechCacheBucket.youdao, 'oldest', payload);
    await cache.write(SpeechCacheBucket.youdao, 'middle', payload);
    await cache.write(SpeechCacheBucket.edge, 'newest', payload);

    // 显式拉开三个文件的 mtime，避免文件系统秒级时间戳同值。
    final files = tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.mp3'))
        .toList();
    expect(files, hasLength(3));
    final now = DateTime.now();
    await cache.read(SpeechCacheBucket.youdao, 'oldest');
    // 直接为三个桶文件设置明确的先后时间。
    for (var i = 0; i < files.length; i += 1) {
      files[i].setLastModifiedSync(
        now.subtract(Duration(minutes: 30 - i * 10)),
      );
    }

    // 总大小 300 字节，上限设为 250 字节 -> 目标 85% = 212 字节 -> 至少删除 1 条。
    final removed = await cache.enforceLimit(250);
    expect(removed, 1);
    final remaining = await cache.stats();
    expect(remaining.totalFiles, 2);
    expect(remaining.totalBytes, 200);
  });
}
