/// 音频内存 LRU 的单测。
///
/// 缓存的价值只有一条：同一个地址不被反复下载。本文件把「命中不下载」
/// 「容量封顶后淘汰最旧」「并发只下载一次」三条性质钉死。
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexiloop/services/audio/audio_cache.dart';
import 'package:lexiloop/services/audio/speech_disk_cache.dart';

import 'audio_fakes.dart';

Uri _url(String term) => Uri.parse('https://example.com/$term.mp3');

void main() {
  late FakeAudioDownloader downloader;
  late AudioCache cache;

  setUp(() {
    downloader = FakeAudioDownloader();
    cache = AudioCache(downloader);
    downloader.openGate();
  });

  /// 某个地址被真正下载了几次（命中缓存不计）。
  int downloadsOf(Uri url) =>
      downloader.downloaded.where((one) => one == url).length;

  test('首次下载后命中缓存不再联网', () async {
    final url = _url('apple');
    final first = await cache.resolve(url);
    downloader.openGate();
    final second = await cache.resolve(url);

    expect(first, isNotNull);
    expect(second, first);
    expect(downloader.downloaded, <Uri>[url]);
    expect(cache.length, 1);
  });

  test('超出容量后淘汰最旧的一条', () async {
    final bounded = AudioCache(downloader, maxEntries: 2);
    final urls = <Uri>[_url('a'), _url('b'), _url('c')];
    for (final url in urls) {
      await bounded.resolve(url);
    }
    expect(bounded.length, 2);

    // 最旧的 a 已被淘汰，再取一次必须重新下载。
    await bounded.resolve(urls.first);
    expect(downloadsOf(urls.first), 2);
  });

  test('读一次即刷新最近使用顺序', () async {
    final bounded = AudioCache(downloader, maxEntries: 2);
    downloader.openGate();
    await bounded.resolve(_url('a'));
    await bounded.resolve(_url('b'));
    // 触碰 a，使 b 成为最旧的一条。
    await bounded.resolve(_url('a'));
    await bounded.resolve(_url('c'));

    // 被淘汰的是 b 而不是 a —— 这正是「读一次即刷新顺序」的证据：
    // 若命中时不刷新顺序，淘汰的会是 a。
    expect(bounded.length, 2);
    expect(downloadsOf(_url('a')), 1);
    expect(downloadsOf(_url('b')), 1);

    // b 已经不在缓存里，再取一次必须重新下载；这一取又挤掉了 a。
    await bounded.resolve(_url('b'));
    expect(downloadsOf(_url('b')), 2);
    expect(downloadsOf(_url('a')), 1);
  });

  test('不同地址各自缓存，互不命中', () async {
    downloader.openGate();
    await cache.resolve(_url('us'));
    await cache.resolve(_url('uk'));

    expect(cache.length, 2);
    expect(downloader.downloaded, hasLength(2));
  });

  test('并发请求同一个地址只下载一次', () async {
    final url = _url('apple');
    final pending = <Future<dynamic>>[
      cache.resolve(url),
      cache.resolve(url),
      cache.resolve(url),
    ];
    await settle(4);

    expect(downloader.downloaded, hasLength(1));
    downloader.openGate();
    final results = await Future.wait(pending);
    expect(results, hasLength(3));
    expect(results.every((bytes) => bytes is Uint8List), isTrue);
  });

  test('下载失败返回 null 且不写入缓存', () async {
    final url = _url('broken');
    downloader.failing.add(url.toString());
    expect(await cache.resolve(url), isNull);
    expect(cache.length, 0);

    // 失败不缓存：下一次仍会重试，而不是永久记成「没有音频」。
    expect(await cache.resolve(url), isNull);
    expect(downloader.downloaded, hasLength(2));
  });

  test('空响应体同样视为失败', () async {
    final url = _url('empty');
    downloader.payloads[url.toString()] = Uint8List(0);
    expect(await cache.resolve(url), isNull);
    expect(cache.length, 0);
  });

  test('clear 之后重新下载', () async {
    downloader.openGate();
    await cache.resolve(_url('apple'));
    cache.clear();

    expect(cache.length, 0);
    await cache.resolve(_url('apple'));
    expect(downloader.downloaded, hasLength(2));
  });

  group('L2 磁盘持久化缓存联动', () {
    test('清空 L1 内存后仍直接命中 L2 磁盘，不触发网络下载', () async {
      final disk = InMemorySpeechDiskCache();
      final tiered = AudioCache(downloader, diskCache: disk);
      final url = _url('offline-word');

      final first = await tiered.resolve(url);
      expect(first, isNotNull);
      expect(downloader.downloaded, hasLength(1));

      // 模拟重启 App：清空内存 LRU，但保留磁盘。
      tiered.clear();
      expect(tiered.length, 0);

      final second = await tiered.resolve(url);
      expect(second, first);
      expect(downloader.downloaded, hasLength(1), reason: '应从磁盘命中，不得再次联网');
      expect(tiered.length, 1, reason: '命中磁盘后应回填 L1 内存');
    });

    test('关闭离线持久化开关时只用内存，不写入磁盘', () async {
      final disk = InMemorySpeechDiskCache();
      final memoryOnly = AudioCache(
        downloader,
        diskCache: disk,
        policy: () => const SpeechCachePolicy(enabled: false, maxBytes: 0),
      );
      final url = _url('no-disk');

      await memoryOnly.resolve(url);
      expect((await disk.stats()).totalFiles, 0);

      memoryOnly.clear();
      await memoryOnly.resolve(url);
      expect(downloader.downloaded, hasLength(2));
    });
  });
}
